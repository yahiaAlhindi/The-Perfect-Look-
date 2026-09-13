-- ============================================================
-- The Perfect Look — Seed (T3: admin account)
-- ============================================================
-- Idempotent: safe to run repeatedly. Creates a single admin
-- account used for initial setup (SRS §17 RBAC).
--
-- Production / online project: NEVER leave the dev default
-- password in place. After applying, sign in as the admin and
-- change the password (or run with your own credentials):
--
--   SELECT public.seed_admin('admin@theperfectlook.ae', 'A-strong-password');
--
-- The dev default below is guarded and documented as such.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- seed_admin(email, password) — create an admin ONLY if the
-- email does not exist yet. Returns the user id.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.seed_admin(p_email TEXT, p_password TEXT)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid          uuid := gen_random_uuid();
    v_email        text := lower(btrim(p_email));
    v_existing_id  uuid;
    v_identity_tbl regclass;
BEGIN
    SELECT id INTO v_existing_id FROM auth.users WHERE email = v_email;
    IF v_existing_id IS NOT NULL THEN
        RETURN v_existing_id;
    END IF;

    -- T18: public sign-ups never self-assign roles (handle_new_user
    -- ignores metadata role unless app.rbac_role_change_authorized is
    -- set). Bootstrap accounts are the sanctioned pathway, so enable
    -- it for the insert and clear it afterwards.
    PERFORM set_config('app.rbac_role_change_authorized', 'true', false);

    INSERT INTO auth.users (
        instance_id, id, aud, role, email,
        encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        v_uid,
        'authenticated',
        'authenticated',
        v_email,
        crypt(p_password, gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}',
        jsonb_build_object(
            'role', 'administrator',
            'full_name', 'The Perfect Look Admin',
            'mobile_number', ''
        ),
        now(),
        now()
    )
    ON CONFLICT (email) DO NOTHING;

    PERFORM set_config('app.rbac_role_change_authorized', 'false', false);

    -- GoTrue identities (needed for password sign-in on current
    -- Supabase). Tolerates a schema without auth.identities.
    SELECT to_regclass('auth.identities') INTO v_identity_tbl;
    IF v_identity_tbl IS NOT NULL THEN
        INSERT INTO auth.identities (
            id, user_id, provider_id, provider, identity_data,
            last_sign_in_at, created_at, updated_at
        ) VALUES (
            v_uid, v_uid, v_uid, 'email',
            jsonb_build_object(
                'sub', v_uid,
                'email', v_email,
                'email_verified', false,
                'phone_verified', false
            ),
            now(), now(), now()
        )
        ON CONFLICT (provider_id, provider) DO NOTHING;
    END IF;

    RETURN v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.seed_admin(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seed_admin(text, text) TO postgres;
GRANT EXECUTE ON FUNCTION public.seed_admin(text, text) TO service_role;

-- ─────────────────────────────────────────────────────────────
-- Default setup admin (LOCAL DEV ONLY — change on the online project).
-- The profiles row is created automatically by the
-- on_auth_user_created trigger (role=admin from raw_user_meta_data).
-- ─────────────────────────────────────────────────────────────

SELECT public.seed_admin(
    'admin@theperfectlook.ae',
    'ChangeMe-Admin-2026!'
);