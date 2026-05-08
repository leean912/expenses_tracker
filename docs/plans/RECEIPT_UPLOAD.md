# Receipt Image Upload Plan (V2)

**Status**: Planned, not started  
**Target**: V2  
**Scope**: Image picker (camera + gallery), compression, Supabase Storage upload, freemium gate

---

## Key Finding: No DB Migration Required

`receipt_url text` already exists on both tables and the RPC already accepts the param:
- `expenses.receipt_url` (schema line 244)
- `split_bills.receipt_url` (schema line 321)
- `create_split_bill` RPC: `p_receipt_url text` param (schema line 727)
- All 3 Flutter forms already pass `'p_receipt_url': null` — just replace null with the URL

The only infrastructure work is **Supabase Storage setup** (manual, one-time in Dashboard).

---

## Storage Architecture

**Bucket**: `receipts`  
**Visibility**: Public-readable, write-restricted to own folder  
**Path format**: `<user_id>/<uuid>.jpg`  
**URL stored in DB**: Permanent Supabase public URL (no expiry, no signed URL complexity)

Why public-readable (not private): Split bill participants need to view the receipt. If the bucket is private, only the uploader can generate signed URLs — Bob can't view Alice's receipt. Public URL with write restriction is the right trade-off.

### Storage Policies (run in Supabase Dashboard → SQL Editor)

```sql
-- Anyone authenticated can view any receipt (needed for split bill participants)
create policy "public read receipts"
  on storage.objects for select
  using (bucket_id = 'receipts');

-- Users can only upload to their own folder
create policy "users upload own receipts"
  on storage.objects for insert
  with check (bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text);

-- Users can only delete their own receipts
create policy "users delete own receipts"
  on storage.objects for delete
  using (bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text);
```

---

## Upload Flow

```
User taps receipt icon (camera/gallery)
  │
  ▼
Show action sheet: "Camera" / "Choose from Gallery"
  │
  ▼
image_picker → returns File (raw, possibly >1MB)
  │
  ▼
flutter_image_compress → compress to <1MB
  │  strategy: start JPEG quality 85%, reduce to 70% then 50% if still >1MB
  │
  ▼
Upload to Supabase Storage
  path: receipts/<user_id>/<uuid>.jpg
  method: supabase.storage.from('receipts').uploadBinary(path, bytes)
  │
  ▼
Get public URL
  supabase.storage.from('receipts').getPublicUrl(path)
  │
  ▼
Store URL in local form state (not yet saved to DB)
  │
  ▼
On form submit → pass receipt_url to INSERT (expenses) or RPC (split bills)
```

---

## New Packages

```
image_picker            — camera + gallery access
flutter_image_compress  — compression before upload
```

Install: `fvm flutter pub add image_picker flutter_image_compress`  
Do NOT edit `pubspec.yaml` manually.

### Platform Config (one-time)

**iOS** — add to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>To attach a receipt photo to your expense</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>To choose a receipt photo from your gallery</string>
```

**Android** — No manifest changes needed. Requires `minSdkVersion >= 21` (verify in `android/app/build.gradle`).

---

## New Service

`lib/core/services/receipt_upload_service.dart`

Single responsibility: pick → compress → upload → return public URL.  
Used by all 3 form files — upload logic lives in exactly one place.

```dart
// Sketch of the service interface
class ReceiptUploadService {
  // Returns the public URL, or null if user cancelled
  Future<String?> pickAndUpload(BuildContext context) async {
    // 1. Show action sheet (Camera / Gallery)
    // 2. image_picker picks file
    // 3. flutter_image_compress compresses to <1MB
    // 4. supabase.storage.from('receipts').uploadBinary(...)
    // 5. return getPublicUrl(path)
  }
}
```

---

## Flutter Files Changed

| File | Change |
|---|---|
| `lib/core/services/receipt_upload_service.dart` | **New file** — pick, compress, upload logic |
| `lib/modules/expenses/presentation/widgets/add_expense_sheet.dart` | Receipt picker for personal expense tab (direct INSERT) + split tab (RPC) |
| `lib/modules/collabs/presentation/widgets/collab_split_bill_sheet.dart` | Receipt picker, pass URL to RPC |
| `lib/modules/contacts/presentation/widgets/group_split_bill_sheet.dart` | Receipt picker, pass URL to RPC |
| Expense detail screen | Thumbnail if `receipt_url != null`, tap to full-screen |
| Split bill detail screen | Thumbnail if `receipt_url != null`, tap to full-screen |

---

## Freemium Gate

**Free users**: Can VIEW receipts — the URL is on the bill row they already have RLS access to. No extra work.  
**Premium users**: Can UPLOAD.

The gate is client-side only (consistent with existing freemium pattern):

```dart
// In receipt icon tap handler (all 3 form files)
if (profile.subscriptionTier == 'free') {
  showUpgradeSheet(context); // existing upgrade sheet
  return;
}
// proceed with ReceiptUploadService.pickAndUpload(context)
```

Freemium pitch copy: *"Attach receipt photos — Premium feature."*

No RPC change needed — a free user who bypasses the client check would fail at the storage policy layer (they'd be uploading to their own folder which the policy allows... actually this means storage doesn't enforce the premium gate). The gate MUST be client-side. This is acceptable — receipt upload is a convenience feature, not a data-integrity gate.

---

## Impact Summary

| Area | Impact | Needs migration? |
|---|---|---|
| DB schema | None — `receipt_url` columns already exist | No |
| Supabase Storage | Create `receipts` bucket + 3 policies | Manual setup only |
| Flutter packages | `image_picker`, `flutter_image_compress` | No |
| iOS `Info.plist` | 2 permission strings | No |
| Android | None (minSdk already ≥ 21 assumed) | No |
| Flutter forms | 3 files get receipt picker UI | No |
| Flutter detail screens | 2 screens show thumbnail | No |
| New service file | 1 new file | No |
| Existing RPCs | No change — `p_receipt_url` param already exists | No |
| RLS | No change | No |

**Zero DB migrations. Zero RPC changes. Zero RLS rewrites.**

---

## Single Receipt Per Record

Each expense and each split bill supports **one receipt only**. This maps cleanly to the single `receipt_url` column on each table.

**UX behaviour:**
- If `receipt_url` is null → show "Add receipt" button (premium gate applies)
- If `receipt_url` is set → show thumbnail; no upload option shown
- To change the receipt, the user must **delete first, then upload again**
  - Delete: sets `receipt_url = null` on the DB row + removes file from Supabase Storage
  - Upload: only available once `receipt_url` is null again

**Delete flow:**
1. User taps the receipt thumbnail → full-screen viewer
2. Full-screen viewer has a delete button (trash icon, premium-only or owner-only)
3. On confirm: `supabase.storage.from('receipts').remove([storagePath])` then UPDATE `receipt_url = null`
4. To reconstruct the storage path from the public URL: parse the path segment after `/receipts/`

**Storage path recovery** (needed for delete):
```dart
// Public URL format: https://<project>.supabase.co/storage/v1/object/public/receipts/<user_id>/<file>.jpg
// Parse back to storage path:
final storagePath = publicUrl.split('/object/public/receipts/').last;
// → "<user_id>/<file>.jpg"
await supabase.storage.from('receipts').remove([storagePath]);
```

This means no separate path column is needed — the public URL is self-describing.

---

## Implementation Order (when ready)

1. Supabase Dashboard: create `receipts` bucket (public) + run 3 storage policies above
2. `fvm flutter pub add image_picker flutter_image_compress`
3. iOS `Info.plist`: add 2 permission strings
4. Build `lib/core/services/receipt_upload_service.dart`
5. `add_expense_sheet.dart` — receipt picker on both personal + split tabs
6. `collab_split_bill_sheet.dart` — receipt picker
7. `group_split_bill_sheet.dart` — receipt picker
8. Expense detail screen — receipt thumbnail + full-screen viewer
9. Split bill detail screen — receipt thumbnail + full-screen viewer
