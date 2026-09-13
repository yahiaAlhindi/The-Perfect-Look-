-- ============================================================
-- The Perfect Look — T8: E.164 mobile normalisation fix
-- ============================================================
-- Migration: 010_mobile_normalisation.sql
-- Depends on: 002_auth_profiles.sql (T5)
-- Source: T8 "server-side validation"; SRS v1 §5.1
--
-- The T5 normaliser (002) mapped a leading-zero local mobile
-- `05XXXXXXXX` to `+97105XXXXXXXX` — the leading `0` of the national
-- number was kept, which is NOT valid E.164 (leading zero must be
-- dropped after the country code). The code comments in 002 and in
-- web/src/lib/supabase/validation.ts both state the intent to output
-- `+9715XXXXXXXX`, so this migration corrects the server-side branch
-- to match (kept in sync with the client normaliser).
--
-- End-to-end consistency is preserved: sign-up stores the same
-- E.164 value that sign-in resolves, and the profile PUT normaliser
-- (T8) produces a clean E.164 mobile for the `profiles` row.
-- ============================================================

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
            NEW.mobile_number := '+971' || substr(NEW.mobile_number, 2);
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