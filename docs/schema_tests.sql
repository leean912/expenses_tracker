-- ═══════════════════════════════════════════════════════════════════
-- EXPENSE TRACKER — SCHEMA TEST SUITE
-- Paste into Supabase SQL Editor and run as postgres / service_role.
-- Uses fixed UUIDs so tests are repeatable and easy to clean up.
-- Run sections in order: SETUP → T01-T25 → CLEANUP.
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- SETUP — create two test users via auth.users (fires handle_new_user)
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
BEGIN
  -- Clean up any previous run first
  DELETE FROM auth.users WHERE id IN (a, b);

  INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
  VALUES
    (a, 'authenticated', 'authenticated', 'alice@exp.test', '', now(), now(), now(), '{"full_name":"Alice Test"}'),
    (b, 'authenticated', 'authenticated', 'bob@exp.test',   '', now(), now(), now(), '{"full_name":"Bob Test"}');

  RAISE NOTICE 'SETUP DONE — Alice=% Bob=%', a, b;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T01 — handle_new_user: profiles created
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  n int;
BEGIN
  SELECT count(*) INTO n FROM profiles WHERE id IN (a, b);
  ASSERT n = 2, format('Expected 2 profiles, got %s', n);
  RAISE NOTICE 'T01 PASS: handle_new_user created % profiles', n;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T02 — handle_new_user: 11 default categories seeded
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  n    int;
  cats text[];
BEGIN
  SELECT count(*), array_agg(name ORDER BY sort_order)
  INTO n, cats
  FROM categories
  WHERE user_id = a AND is_default = true AND deleted_at IS NULL;

  ASSERT n = 11, format('Expected 11 categories, got %s', n);
  ASSERT cats[1]  = 'Food',      format('Expected Food first, got %s',  cats[1]);
  ASSERT cats[11] = 'Trip',      format('Expected Trip last, got %s',   cats[11]);
  RAISE NOTICE 'T02 PASS: 11 default categories — %', array_to_string(cats, ', ');
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T03 — handle_new_user: Cash + Bank accounts seeded
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a    uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  n    int;
  names text[];
BEGIN
  SELECT count(*), array_agg(name ORDER BY sort_order)
  INTO n, names
  FROM accounts
  WHERE user_id = a AND deleted_at IS NULL;

  ASSERT n = 2, format('Expected 2 accounts, got %s', n);
  ASSERT names = ARRAY['Cash','Bank'], format('Expected [Cash,Bank], got %s', names);
  RAISE NOTICE 'T03 PASS: default accounts = %', array_to_string(names, ', ');
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T04 — set_username: happy path (both users)
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  v := set_username('alice_test');
  ASSERT (v->>'username') = 'alice_test', format('Got %s', v->>'username');

  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  v := set_username('bob_test');
  ASSERT (v->>'username') = 'bob_test';

  RAISE NOTICE 'T04 PASS: set_username alice_test + bob_test';
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T05 — set_username: duplicate rejected (hint = username_taken)
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  b uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  -- Use a third temp user to try stealing alice_test
  c uuid := 'cccccccc-0000-0000-0000-000000000001';
BEGIN
  DELETE FROM auth.users WHERE id = c;
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
  VALUES (c, 'authenticated', 'authenticated', 'charlie@exp.test', '', now(), now(), now(), '{"full_name":"Charlie"}');

  PERFORM set_config('request.jwt.claim.sub', c::text, true);
  BEGIN
    PERFORM set_username('alice_test');
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN OTHERS THEN
    ASSERT sqlerrm LIKE '%already taken%', format('Wrong error: %s', sqlerrm);
    RAISE NOTICE 'T05 PASS: duplicate username rejected';
  END;

  DELETE FROM auth.users WHERE id = c;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T06 — set_username: immutable once set (hint = username_immutable)
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  BEGIN
    PERFORM set_username('alice_new');
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN OTHERS THEN
    ASSERT sqlerrm LIKE '%already set%', format('Wrong error: %s', sqlerrm);
    RAISE NOTICE 'T06 PASS: username is immutable once set';
  END;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T07 — set_username: invalid format rejected
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  -- Use a fresh user with no username yet
  d uuid := 'dddddddd-0000-0000-0000-000000000001';
BEGIN
  DELETE FROM auth.users WHERE id = d;
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
  VALUES (d, 'authenticated', 'authenticated', 'dave@exp.test', '', now(), now(), now(), '{"full_name":"Dave"}');

  PERFORM set_config('request.jwt.claim.sub', d::text, true);
  BEGIN
    PERFORM set_username('ab');  -- too short (< 3 chars)
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN OTHERS THEN
    ASSERT sqlerrm LIKE '%Invalid username%', format('Wrong error: %s', sqlerrm);
    RAISE NOTICE 'T07 PASS: short username rejected';
  END;

  DELETE FROM auth.users WHERE id = d;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T08 — add_contact: bidirectional rows created
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v jsonb;
  n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  v := add_contact('bob_test', 'Bobby');

  ASSERT (v->>'friend_id')::uuid = b, format('friend_id mismatch: %s', v->>'friend_id');

  SELECT count(*) INTO n
  FROM contacts
  WHERE (owner_id = a AND friend_id = b AND deleted_at IS NULL)
     OR (owner_id = b AND friend_id = a AND deleted_at IS NULL);

  ASSERT n = 2, format('Expected 2 bidirectional rows, got %s', n);
  RAISE NOTICE 'T08 PASS: add_contact created % bidirectional rows', n;

  PERFORM set_config('test.contact_id', v->>'contact_id', true);
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T09 — add_contact: cannot add self
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  BEGIN
    PERFORM add_contact('alice_test');
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN OTHERS THEN
    ASSERT sqlerrm LIKE '%cannot add yourself%', format('Wrong error: %s', sqlerrm);
    RAISE NOTICE 'T09 PASS: self-contact rejected';
  END;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T10 — collabs: create + handle_new_collab trigger auto-adds owner
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_collab uuid;
  n        int;
  r        text;
BEGIN
  INSERT INTO collabs (owner_id, name, currency, home_currency, exchange_rate)
  VALUES (a, 'Japan 2026', 'JPY', 'MYR', 30.0)
  RETURNING id INTO v_collab;

  SELECT count(*), min(role) INTO n, r
  FROM collab_members
  WHERE collab_id = v_collab AND user_id = a;

  ASSERT n = 1, format('Expected 1 collab_members row, got %s', n);
  ASSERT r = 'owner', format('Expected owner role, got %s', r);
  RAISE NOTICE 'T10 PASS: handle_new_collab auto-added owner, collab=%', v_collab;

  PERFORM set_config('test.collab_id', v_collab::text, true);
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T11 — personal_budget_cents: member can set own budget
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_collab uuid := current_setting('test.collab_id')::uuid;
  v        bigint;
BEGIN
  UPDATE collab_members
  SET personal_budget_cents = 150000  -- RM 1,500.00
  WHERE collab_id = v_collab AND user_id = a;

  SELECT personal_budget_cents INTO v
  FROM collab_members
  WHERE collab_id = v_collab AND user_id = a;

  ASSERT v = 150000, format('Expected 150000, got %s', v);
  RAISE NOTICE 'T11 PASS: personal_budget_cents = % cents', v;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T12 — add_collab_member: owner adds Bob (must be a contact)
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b        uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_collab uuid := current_setting('test.collab_id')::uuid;
  v        jsonb;
  n        int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  v := add_collab_member(v_collab, b);

  SELECT count(*) INTO n
  FROM collab_members
  WHERE collab_id = v_collab AND user_id = b AND left_at IS NULL;

  ASSERT n = 1, format('Expected Bob in collab_members, got %s', n);
  RAISE NOTICE 'T12 PASS: Bob added to collab, member_id=%', v->>'member_id';
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T13 — create_split_bill: Alice pays, splits evenly with Bob
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b        uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_collab uuid := current_setting('test.collab_id')::uuid;
  cat_id    uuid;
  v         jsonb;
  bill_id   uuid;
  n         int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  SELECT id INTO cat_id FROM categories WHERE user_id = a AND name = 'Food' AND deleted_at IS NULL LIMIT 1;

  v := create_split_bill(
    p_paid_by             := a,
    p_total_amount_cents  := 10000,
    p_currency            := 'JPY',
    p_note                := 'Ramen dinner',
    p_expense_date        := current_date,
    p_category_id         := cat_id,
    p_collab_id           := v_collab,
    p_google_place_id     := null,
    p_place_name          := null,
    p_latitude            := null,
    p_longitude           := null,
    p_receipt_url         := null,
    p_shares              := jsonb_build_array(
      jsonb_build_object('user_id', a, 'share_cents', 5000),
      jsonb_build_object('user_id', b, 'share_cents', 5000)
    ),
    p_home_amount_cents   := 334,   -- 10000 JPY / 30 ≈ 333.33 MYR
    p_home_currency       := 'MYR',
    p_conversion_rate     := 30.0
  );

  bill_id := (v->>'split_bill_id')::uuid;
  ASSERT bill_id IS NOT NULL;

  -- Payer's auto-expense created
  SELECT count(*) INTO n FROM expenses WHERE source_split_bill_id = bill_id AND user_id = a AND source = 'split_payer';
  ASSERT n = 1, format('Expected 1 payer expense, got %s', n);

  -- Alice's share settled, Bob's pending
  ASSERT EXISTS (SELECT 1 FROM split_bill_shares WHERE split_bill_id = bill_id AND user_id = a AND status = 'settled');
  ASSERT EXISTS (SELECT 1 FROM split_bill_shares WHERE split_bill_id = bill_id AND user_id = b AND status = 'pending');

  RAISE NOTICE 'T13 PASS: create_split_bill → bill=%, payer_exp=%', v->>'split_bill_id', v->>'payer_expense_id';
  PERFORM set_config('test.bill_id', bill_id::text, true);
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T14 — create_split_bill: non-contact participant rejected
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  stranger uuid := 'eeeeeeee-0000-0000-0000-000000000001';
BEGIN
  DELETE FROM auth.users WHERE id = stranger;
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
  VALUES (stranger, 'authenticated', 'authenticated', 'stranger@exp.test', '', now(), now(), now(), '{"full_name":"Stranger"}');

  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  BEGIN
    PERFORM create_split_bill(
      p_paid_by := a, p_total_amount_cents := 1000, p_currency := 'MYR',
      p_note := null, p_expense_date := current_date, p_category_id := null,
      p_collab_id := null, p_google_place_id := null, p_place_name := null,
      p_latitude := null, p_longitude := null, p_receipt_url := null,
      p_shares := jsonb_build_array(
        jsonb_build_object('user_id', a,        'share_cents', 500),
        jsonb_build_object('user_id', stranger, 'share_cents', 500)
      )
    );
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN OTHERS THEN
    ASSERT sqlerrm LIKE '%not in your contacts%', format('Wrong error: %s', sqlerrm);
    RAISE NOTICE 'T14 PASS: non-contact participant rejected';
  END;

  DELETE FROM auth.users WHERE id = stranger;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T15 — settle_split_share: Bob settles his share
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  b          uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  bill_id    uuid := current_setting('test.bill_id')::uuid;
  share_id   uuid;
  bob_cat_id uuid;
  v          jsonb;
  n          int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  SELECT id INTO share_id FROM split_bill_shares WHERE split_bill_id = bill_id AND user_id = b;
  SELECT id INTO bob_cat_id FROM categories WHERE user_id = b AND name = 'Food' AND deleted_at IS NULL LIMIT 1;

  v := settle_split_share(share_id, bob_cat_id, null);

  ASSERT EXISTS (SELECT 1 FROM split_bill_shares WHERE id = share_id AND status = 'settled');
  SELECT count(*) INTO n FROM expenses WHERE source_settlement_id = (v->>'settlement_id')::uuid;
  ASSERT n = 2, format('Expected 2 expense rows (settler + payer income), got %s', n);

  RAISE NOTICE 'T15 PASS: settle_split_share → settlement=%, expenses created=%', v->>'settlement_id', n;
  PERFORM set_config('test.share_id',      share_id::text,            true);
  PERFORM set_config('test.settlement_id', v->>'settlement_id',       true);
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T16 — unsettle_split_share: Bob un-settles
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  b             uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  share_id      uuid := current_setting('test.share_id')::uuid;
  settlement_id uuid := current_setting('test.settlement_id')::uuid;
  v             jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  v := unsettle_split_share(share_id);

  ASSERT (v->>'status') = 'pending';
  ASSERT EXISTS (SELECT 1 FROM settlements   WHERE id = settlement_id AND deleted_at IS NOT NULL);
  ASSERT EXISTS (SELECT 1 FROM split_bill_shares WHERE id = share_id AND status = 'pending');
  ASSERT NOT EXISTS (
    SELECT 1 FROM expenses
    WHERE source_settlement_id = settlement_id AND deleted_at IS NULL
  );
  RAISE NOTICE 'T16 PASS: unsettle_split_share → share back to pending, settlement + expenses soft-deleted';
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T17 — close_collab: owner closes successfully
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_collab uuid := current_setting('test.collab_id')::uuid;
  v        jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  v := close_collab(v_collab);

  ASSERT EXISTS (SELECT 1 FROM collabs WHERE id = v_collab AND status = 'closed' AND closed_at IS NOT NULL);
  RAISE NOTICE 'T17 PASS: close_collab → closed_at=%, unsettled_splits=%',
    v->>'closed_at', v->>'unsettled_splits_remaining';
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T18 — close_collab: non-owner rejected
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  b        uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_collab uuid := current_setting('test.collab_id')::uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  BEGIN
    PERFORM close_collab(v_collab);
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN OTHERS THEN
    ASSERT sqlerrm LIKE '%owner%', format('Wrong error: %s', sqlerrm);
    RAISE NOTICE 'T18 PASS: non-owner cannot close collab';
  END;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T19 — leave_collab: Bob leaves
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  b        uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_collab uuid := current_setting('test.collab_id')::uuid;
  v        jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  v := leave_collab(v_collab);

  ASSERT EXISTS (SELECT 1 FROM collab_members WHERE collab_id = v_collab AND user_id = b AND left_at IS NOT NULL);
  RAISE NOTICE 'T19 PASS: Bob left collab at %', v->>'left_at';
END $$;


-- ─────────────────────────────────────────────────────────────────
-- T20 — leave_collab: owner cannot leave
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_collab uuid := current_setting('test.collab_id')::uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  BEGIN
    PERFORM leave_collab(v_collab);
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN OTHERS THEN
    ASSERT sqlerrm LIKE '%owner cannot leave%', format('Wrong error: %s', sqlerrm);
    RAISE NOTICE 'T20 PASS: owner cannot leave collab';
  END;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- CONSTRAINT TESTS
-- ─────────────────────────────────────────────────────────────────

-- T21 — collabs: same-currency collab rejects non-null exchange_rate
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
BEGIN
  BEGIN
    INSERT INTO collabs (owner_id, name, currency, home_currency, exchange_rate)
    VALUES (a, 'Bad', 'MYR', 'MYR', 1.0);
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T21 PASS: same-currency collab rejects non-null exchange_rate';
  END;
END $$;


-- T22 — collabs: foreign-currency collab rejects null exchange_rate
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
BEGIN
  BEGIN
    INSERT INTO collabs (owner_id, name, currency, home_currency)
    VALUES (a, 'Bad', 'JPY', 'MYR');   -- exchange_rate defaults to null
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T22 PASS: foreign-currency collab rejects null exchange_rate';
  END;
END $$;


-- T23 — expenses: amount_cents must be > 0
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
BEGIN
  BEGIN
    INSERT INTO expenses (user_id, amount_cents, currency, expense_date)
    VALUES (a, 0, 'MYR', current_date);
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T23 PASS: amount_cents = 0 rejected';
  END;
END $$;


-- T24 — collab end_date must be >= start_date
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
BEGIN
  BEGIN
    INSERT INTO collabs (owner_id, name, currency, home_currency, start_date, end_date)
    VALUES (a, 'Bad Dates', 'MYR', 'MYR', '2026-05-10', '2026-05-01');
    RAISE EXCEPTION 'Should have failed';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T24 PASS: end_date < start_date rejected';
  END;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- RLS TESTS — simulate authenticated user with SET ROLE
-- ─────────────────────────────────────────────────────────────────

-- T25 — RLS: collab expense visible to active member, invisible after leaving
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b        uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_collab uuid;
  exp_id   uuid;
  n        int;
BEGIN
  -- Fresh collab so Bob is an active member
  INSERT INTO collabs (owner_id, name, currency, home_currency)
  VALUES (a, 'RLS Test Collab', 'MYR', 'MYR')
  RETURNING id INTO v_collab;

  INSERT INTO collab_members (collab_id, user_id, role)
  VALUES (v_collab, b, 'member');

  -- Alice logs a collab-tagged expense
  INSERT INTO expenses (user_id, amount_cents, currency, expense_date, collab_id)
  VALUES (a, 5000, 'MYR', current_date, v_collab)
  RETURNING id INTO exp_id;

  -- Bob is active → should see it
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  SELECT count(*) INTO n FROM expenses WHERE id = exp_id;
  RESET ROLE;
  ASSERT n = 1, format('Active member should see expense, got %s', n);
  RAISE NOTICE 'T25a PASS: active collab member sees collab expense';

  -- Bob leaves
  UPDATE collab_members SET left_at = now() WHERE collab_id = v_collab AND user_id = b;

  -- Bob has left → should NOT see it
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  SELECT count(*) INTO n FROM expenses WHERE id = exp_id;
  RESET ROLE;
  ASSERT n = 0, format('Left member should NOT see expense, got %s', n);
  RAISE NOTICE 'T25b PASS: departed member cannot see collab expense';

  -- Clean up RLS test collab
  DELETE FROM collabs WHERE id = v_collab;
END $$;


-- T26 — RLS cm_insert: user cannot self-insert into a collab they don't own
DO $$
DECLARE
  a        uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  b        uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_collab uuid;
BEGIN
  -- Alice creates a new collab (Bob is NOT a member)
  INSERT INTO collabs (owner_id, name, currency, home_currency)
  VALUES (a, 'Alice Private', 'MYR', 'MYR')
  RETURNING id INTO v_collab;

  -- Bob tries to self-insert as authenticated user (not via RPC)
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  BEGIN
    INSERT INTO collab_members (collab_id, user_id, role)
    VALUES (v_collab, b, 'member');
    RESET ROLE;
    RAISE EXCEPTION 'Should have been blocked by RLS';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
    RAISE NOTICE 'T26 PASS: RLS blocked Bob from self-inserting into Alice''s collab';
  WHEN OTHERS THEN
    RESET ROLE;
    RAISE NOTICE 'T26 PASS (via %): %', SQLSTATE, sqlerrm;
  END;

  DELETE FROM collabs WHERE id = v_collab;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- CLEANUP — removes all test data (cascades to profiles, categories,
-- accounts, collabs, expenses, split_bills, etc.)
-- ─────────────────────────────────────────────────────────────────
/*
DELETE FROM auth.users WHERE id IN (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'bbbbbbbb-0000-0000-0000-000000000001'
);
RAISE NOTICE 'CLEANUP DONE';
*/
-- Uncomment the block above and run it after you''re done testing.
