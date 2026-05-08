import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../service_locator.dart';
import '../theme/app_colors.dart';

class ReceiptUploadService {
  static final _picker = ImagePicker();
  static const _uuid = Uuid();

  // Returns the public URL, or null if user cancelled or upload failed.
  static Future<String?> pickAndUpload(
    BuildContext context,
    String userId,
  ) async {
    final source = await _showSourceSheet(context);
    if (source == null) return null;

    final picked = await _picker.pickImage(source: source, imageQuality: 100);
    if (picked == null) return null;

    final compressed = await _compressToFile(picked.path);
    if (compressed == null) return null;

    final path = '$userId/${_uuid.v4()}.jpg';
    try {
      await supabase.storage.from('receipts').upload(
            path,
            compressed,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      return supabase.storage.from('receipts').getPublicUrl(path);
    } catch (_) {
      return null;
    } finally {
      await compressed.delete();
    }
  }

  // Deletes from Storage by parsing the path out of the public URL.
  static Future<void> deleteByUrl(String publicUrl) async {
    try {
      final path = publicUrl.split('/object/public/receipts/').last;
      await supabase.storage.from('receipts').remove([path]);
    } catch (_) {}
  }

  static Future<ImageSource?> _showSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.textPrimary,
              ),
              title: const Text(
                'Camera',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const Divider(height: 1, color: AppColors.border),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.textPrimary,
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  // Compresses to <1MB and writes to a temp file.
  static Future<File?> _compressToFile(String sourcePath) async {
    final tmpDir = await getTemporaryDirectory();
    final outPath = '${tmpDir.path}/${_uuid.v4()}.jpg';

    for (final quality in [85, 70, 50]) {
      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        outPath,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result == null) return null;
      final size = await result.length();
      if (size <= 1024 * 1024) return File(result.path);
    }
    return null;
  }
}
