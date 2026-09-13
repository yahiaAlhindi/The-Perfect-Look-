-- ============================================================
-- The Perfect Look — T8: Profile API support
-- ============================================================
-- Migration: 003_profile_api.sql
-- Depends on: 001_schema.sql (T3) + 002_auth_profiles.sql (T5)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T8, SRS v1 §7/§16/§17
--
-- Responsibilities:
--   1. Restrict self-service email/mobile changes on profiles.
--      `PUT /profile` only exposes full_name / dob / gender /
--      preferred_language; email/mobile changes are gated pending the
--      T35 client decision. This trigger is the DB-level guard so a
--      direct PostgREST call cannot bypass the client API (defence in
--      depth — mirrors prevent_self_role_change from 001_schema.sql).
--      Admins / staff acting on behalf of another user (auth.uid() !=
--      OLD.id) and the service role are unaffected.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. PREVENT SELF-SERVICE CONTACT CHANGES (gated pending T35)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prevent_self_contact_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() = OLD.id AND (
        NEW.email        IS DISTINCT FROM OLD.email OR
        NEW.mobile_number IS DISTINCT FROM OLD.mobile_number
    ) THEN
        RAISE EXCEPTION 'Email and mobile number changes require verification — contact the clinic';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_self_contact_change ON public.profiles;

CREATE TRIGGER trg_prevent_self_contact_change
    BEFORE UPDATE OF email, mobile_number
    ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_self_contact_change();