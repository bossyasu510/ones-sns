-- ═══════════════════════════════════════════════════════════
-- ONEs SNS: Supabase Auth 移行 SQL
-- 実行場所: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════
--
-- ⚠️  実行前に必ず以下を確認してください:
--   1. Supabase Dashboard → Authentication → Providers → Email
--      → "Confirm email" を OFF にする（招待制のため不要）
--   2. このSQLを全文コピーして SQL Editor に貼り付け → Run
--
-- ═══════════════════════════════════════════════════════════

-- ──────────────────────────────────────
-- Section 1: members テーブルにカラム追加
-- ──────────────────────────────────────

-- Supabase Auth の user ID を紐付けるカラム
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS auth_uid uuid UNIQUE;

-- メールアドレス（ログインID）
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS email text;

-- ──────────────────────────────────────
-- Section 2: claimed_member_id() を更新
--   JWT認証（auth.uid）を優先し、ヘッダーをフォールバック
--   既存のRLSポリシーはこの関数を使っているため
--   この関数を更新するだけで全ポリシーが対応する
-- ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.claimed_member_id()
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid;
  v_mid text;
BEGIN
  -- 1. Supabase Auth JWT があればそちらを優先
  v_uid := auth.uid();
  IF v_uid IS NOT NULL THEN
    SELECT id INTO v_mid FROM public.members WHERE auth_uid = v_uid;
    IF v_mid IS NOT NULL THEN
      RETURN v_mid;
    END IF;
  END IF;

  -- 2. フォールバック: x-member-id ヘッダー（移行期間のみ）
  RETURN coalesce(
    current_setting('request.headers', true)::jsonb->>'x-member-id',
    ''
  );
END;
$$;

-- ──────────────────────────────────────
-- Section 3: claim_member_account() — 既存メンバーの移行用 RPC
--   既存メンバーが Supabase Auth アカウントを作成した後、
--   自分の member レコードに auth_uid を紐付ける
-- ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.claim_member_account(p_member_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid;
  v_email text;
  v_existing_member text;
BEGIN
  -- 認証チェック
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '認証されていません');
  END IF;

  -- このAuthユーザーが既に別のメンバーを紐付けていないか
  SELECT id INTO v_existing_member FROM public.members WHERE auth_uid = v_uid;
  IF v_existing_member IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'このアカウントは既にメンバーに紐付けられています');
  END IF;

  -- 対象メンバーが存在し、未紐付けであること
  IF NOT EXISTS (
    SELECT 1 FROM public.members
    WHERE id = p_member_id AND auth_uid IS NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'メンバーが見つからないか、既に認証済みです');
  END IF;

  -- Auth ユーザーのメールを取得
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;

  -- 紐付け実行
  UPDATE public.members
  SET auth_uid = v_uid, email = v_email
  WHERE id = p_member_id AND auth_uid IS NULL;

  RETURN jsonb_build_object('ok', true, 'member_id', p_member_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_member_account(text) TO authenticated;

-- ──────────────────────────────────────
-- Section 4: create_member_with_auth() — 新規メンバー登録 RPC
--   Supabase Auth でアカウント作成後、メンバーレコードを作成
-- ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_member_with_auth(
  p_name text,
  p_invite_code text,
  p_emoji text DEFAULT '🎉'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid;
  v_email text;
  v_code record;
  v_new_id text;
  v_new_my_code text;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_i int;
  v_rand_code text := '';
BEGIN
  -- 認証チェック
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', '認証されていません');
  END IF;

  -- 既にメンバー登録済みでないか
  IF EXISTS (SELECT 1 FROM public.members WHERE auth_uid = v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', '既に登録済みです');
  END IF;

  -- 招待コード検証
  SELECT * INTO v_code FROM public.invite_codes
  WHERE code = upper(p_invite_code);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', '招待コードが無効です');
  END IF;

  -- ニックネーム重複チェック
  IF EXISTS (SELECT 1 FROM public.members WHERE name = p_name) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'このニックネームは既に使用されています');
  END IF;

  -- メール取得
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;

  -- ID生成
  v_new_id := 'm' || extract(epoch from clock_timestamp())::bigint::text;

  -- 招待コード生成 (ONES-XXXX)
  FOR v_i IN 1..4 LOOP
    v_rand_code := v_rand_code || substr(v_chars, floor(random() * length(v_chars) + 1)::int, 1);
  END LOOP;
  v_new_my_code := 'ONES-' || v_rand_code;

  -- メンバー作成
  INSERT INTO public.members (
    id, name, emoji, code, my_code,
    invited_by, invited_by_id,
    join_date, status, role,
    auth_uid, email
  ) VALUES (
    v_new_id, p_name, p_emoji, upper(p_invite_code), v_new_my_code,
    v_code.issued_by, v_code.issued_by_id,
    to_char(current_date, 'YYYY-MM-DD'), 'active', 'member',
    v_uid, v_email
  );

  -- 新メンバーの招待コードを発行
  INSERT INTO public.invite_codes (code, issued_by, issued_by_id, used_by, status)
  VALUES (v_new_my_code, p_name, v_new_id, '未使用', 'unused');

  RETURN jsonb_build_object(
    'ok', true,
    'member_id', v_new_id,
    'name', p_name,
    'my_code', v_new_my_code,
    'emoji', p_emoji,
    'invited_by', v_code.issued_by
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_member_with_auth(text, text, text) TO authenticated;

-- ──────────────────────────────────────
-- Section 5: 確認クエリ
-- ──────────────────────────────────────

SELECT
  column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'members'
  AND column_name IN ('auth_uid', 'email')
ORDER BY column_name;
