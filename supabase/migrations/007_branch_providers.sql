-- ============================================================
-- The Perfect Look — T13: Branch provider list for the picker
-- ============================================================
-- Migration: 007_branch_providers.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             004_branches_client_number_pricing.sql (T37),
--             006_availability_engine.sql (T12, merged as PR #10)
--
-- get_branch_providers() lists the active staff assigned to a branch
-- (primary first). The availability picker (T13) uses it for the
-- optional "choose a provider" step, and feeds the chosen id to
-- get_availability(p_staff_id := ...).
--
-- The function is SECURITY DEFINER because it reads past the public
-- profiles/staff RLS: it exposes only the summary fields the picker
-- needs — no PII beyond the staff display name.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_branch_providers(p_branch_id uuid)
RETURNS TABLE (
    id             uuid,
    full_name      text,
    title          text,
    specializations text[],
    active         boolean,
    primary_branch boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT s.id,
           p.full_name,
           s.title,
           s.specializations,
           s.active,
           sb.primary_branch
      FROM public.staff s
      JOIN public.profiles p       ON p.id = s.profile_id
      JOIN public.staff_branches sb
        ON sb.staff_id = s.id
       AND sb.branch_id = p_branch_id
       AND sb.active
     WHERE s.active = true
     ORDER BY sb.primary_branch DESC, p.full_name;
$$;

REVOKE ALL ON FUNCTION public.get_branch_providers(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_branch_providers(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_branch_providers(uuid) TO authenticated;