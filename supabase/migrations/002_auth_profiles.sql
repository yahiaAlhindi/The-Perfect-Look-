-- ============================================================
-- The Perfect Look — T5: Auth & Session API support
-- ============================================================
-- Migration: 002_auth_profiles.sql
-- Depends on: 001_schema.sql (T3) — tables, enums, RLS, and the
--   handle_new_user() trigger on auth.users.
-- Source: PROJECT_TASKS_BREAKDOWN.md §T5, SRS v1 §5/§6/§7/§17
--
-- Responsibilities:
--   1. Normalise mobile_number (UAE → E.164) and lower-case email
--      on profiles via a BEFORE trigger (single source of truth, so
--      both Auth sign-up and direct inserts are covered).
--   2. Enforce required contact fields on profiles (SRS §5).
--   3. Require mobile_number in sign-up metadata so every new auth
--      user gets a complete profiles row (SRS §5 "Mobile required").
--   4. resolve_login_identifier() RPC — lets the client resolve
--      "email OR mobile" sign-in to an auth email (SRS §6).
-- Uniqueness (email + mobile) is enforced by the unique indexes
-- created in 001_schema.sql; failures surface as mapped client
-- errors (code 23505 / unique_violation).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. NORMALISE CONTACT FIELDS
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.normalize_profile_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Lower-case + trim email
    IF NEW.email IS NOT NULL THEN
        NEW.email := lower(trim(NEW.email));
    END IF;

    -- Normalise UAE mobile numbers to E.164
    IF NEW.mobile_number IS NOT NULL THEN
        -- Strip separators: spaces, dashes, parentheses, dots
        NEW.mobile_number := regexp_replace(NEW.mobile_number, '[\s\-\(\)\.]', '', 'g');

        -- 0XXXXXXXXX (leading zero, UAE local) -> +971XXXXXXXXX
        IF NEW.mobile_number ~ '^0[5-9]\d{8}$' THEN
            NEW.mobile_number := '+971' || NEW.mobile_number;
        -- 9715XXXXXXXX (no leading +) -> +9715XXXXXXXX
        ELSIF NEW.mobile_number ~ '^971[5-9]\d{8}$' THEN
            NEW.mobile_number := '+' || NEW.mobile_number;
        -- 9-digit local without leading zero (e.g. 55XXXXXXX) -> +9715XXXXXXX
        ELSIF NEW.mobile_number ~ '^[5-9]\d{8}$' THEN
            NEW.mobile_number := '+971' || NEW.mobile_number;
        END IF;

        -- Final guard: must be E.164-ish (+, 1-3 digit country code, 6-14 digits)
        IF NEW.mobile_number !~ '^\+[1-9]\d{6,14}$' THEN
            RAISE EXCEPTION 'Mobile number is not in a valid international format';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_profile_contact ON public.profiles;

CREATE TRIGGER trg_normalize_profile_contact
    BEFORE INSERT OR UPDATE OF mobile_number, email
    ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.normalize_profile_contact();

-- ─────────────────────────────────────────────────────────────
-- 2. ENFORCE REQUIRED CONTACT FIELDS (SRS §5)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.enforce_profile_required_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.email IS NULL OR trim(NEW.email) = '' THEN
        RAISE EXCEPTION 'Email address is required';
    END IF;
    IF NEW.mobile_number IS NULL OR trim(NEW.mobile_number) = '' THEN
        RAISE EXCEPTION 'Mobile number is required';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_required_fields ON public.profiles;

CREATE TRIGGER trg_enforce_profile_required_fields
    BEFORE INSERT
    ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_profile_required_fields();

-- ─────────────────────────────────────────────────────────────
-- 3. SIGN-UP REQUIRES MOBILE (replaces 001's version)
--    Every new auth user gets a complete profiles row; a missing
--    mobile_number aborts the auth.users insert (a clean failure
--    instead of a partial account).
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.raw_user_meta_data ->> 'mobile_number' IS NULL
       OR trim(NEW.raw_user_meta_data ->> 'mobile_number') = '' THEN
        RAISE EXCEPTION 'Mobile number is required for registration';
    END IF;

    INSERT INTO public.profiles (id, full_name, mobile_number, email, role)
    VALUES (
        NEW.id,
        COALESCE(trim(NEW.raw_user_meta_data ->> 'full_name'), ''),
        NEW.raw_user_meta_data ->> 'mobile_number',
        lower(NEW.email),
        COALESCE((NEW.raw_user_meta_data ->> 'role')::user_role, 'patient')
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name     = EXCLUDED.full_name,
        mobile_number = EXCLUDED.mobile_number,
        email         = EXCLUDED.email;
    RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 4. LOGIN IDENTIFIER RESOLVER (SRS §6: email OR mobile)
--    SECURITY DEFINER so anonymous sign-in can resolve a mobile to
--    its account email. Returns ONLY the auth email — never any
--    other profile data (SRS §17).
-- ─────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.resolve_login_identifier(TEXT);

CREATE OR REPLACE FUNCTION public.resolve_login_identifier(identifier text)
RETURNS TABLE(email text)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT p.email
    FROM public.profiles p
    WHERE lower(p.email) = lower(trim(identifier))
       OR p.mobile_number = identifier
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.resolve_login_identifier(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_login_identifier(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.resolve_login_identifier(TEXT) TO authenticated;