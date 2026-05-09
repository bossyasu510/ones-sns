-- =============================================================================
-- ONEs SNS: get_my_profile() 関数追加
-- JWT認証済みユーザーが自分のメンバー情報を取得するための関数
-- SECURITY DEFINER のため RLS をバイパスして確実にデータを返す
--
-- 使い方: Supabase Dashboard → SQL Editor → 貼り付け → Run
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid;
  v_member record;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_member FROM public.members WHERE auth_uid = v_uid;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'id', v_member.id,
    'name', v_member.name,
    'emoji', v_member.emoji,
    'role', v_member.role,
    'code', v_member.code,
    'my_code', v_member.my_code,
    'invited_by', v_member.invited_by,
    'join_date', v_member.join_date,
    'status', v_member.status,
    'auth_uid', v_member.auth_uid,
    'email', v_member.email
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_profile() TO authenticated;

-- 確認（Run 後に「get_my_profile」が表示されればOK）
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'get_my_profile';
