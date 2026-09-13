/**
 * T18 RBAC data-layer: role helpers, invitation lifecycle, and
 * branch-scoped team management.  Enforcement lives entirely in the
 * database (RLS + SECURITY DEFINER RPCs); this module only surfaces
 * the mapped errors and keeps UI code free of raw RPC boilerplate.
 */

import { supabase } from './client'
import type { InviteableRole, StaffInvitation, UserRole } from './types'
import { mapError, type MappedError } from './errors'
import { validateEmail, normalizeMobile, isValidMobile } from './validation'

// ── Types ─────────────────────────────────────────────────────

export interface RoleResult {
  role: UserRole | null
  error: MappedError | null
}

export interface InviteInput {
  email: string
  full_name: string
  mobile: string
  role: InviteableRole
  branch_ids: string[]
  title?: string | null
}

export interface Result {
  error: MappedError | null
}

export interface InviteResult extends Result {
  invitation?: StaffInvitation | null
}

export interface InvitationListResult {
  invitations: StaffInvitation[]
  error: MappedError | null
}

// ── Role helpers (RLS-driven) ─────────────────────────────────

/**
 * Fetch the current user's RBAC role via the `current_role` RPC.
 * Returns `null` for unauthenticated or anon sessions.
 */
export async function currentRole(): Promise<RoleResult> {
  const { data, error } = await supabase.rpc('current_role')
  if (error) return { role: null, error: mapError(error) }
  return { role: (data as UserRole | null) ?? null, error: null }
}

/** Check if the current user holds the super_admin role. */
export async function isSuperAdmin(): Promise<boolean> {
  const { data } = await supabase.rpc('is_super_admin')
  return (data as boolean) ?? false
}

// ── Invitation lifecycle ───────────────────────────────────────

/**
 * Boundary validation for an invitation payload. Returns errors
 * keyed to form fields so UI can map them to `<FormError>`.
 */
export function validateInvitePayload(input: InviteInput): Record<string, string> {
  const errors: Record<string, string> = {}

  if (!validateEmail(input.email)) {
    errors.email = 'Please enter a valid email address'
  }
  if (!input.full_name.trim() || input.full_name.trim().length < 2) {
    errors.full_name = 'Full name is required'
  }
  const mobile = normalizeMobile(input.mobile)
  if (!isValidMobile(mobile)) {
    errors.mobile = 'Please enter a valid UAE mobile number'
  }
  if (!input.role) {
    errors.role = 'A role is required'
  }
  if (!input.branch_ids || input.branch_ids.length === 0) {
    errors.branch_ids = 'Assign at least one branch'
  }
  return errors
}

/**
 * Send a staff invitation. Validates the payload, normalises the
 * mobile, and delegates to `invite_staff` (RPC, SRS §27.1).
 * The invite email is sent asynchronously by a DB trigger.
 */
export async function inviteStaff(input: InviteInput): Promise<InviteResult> {
  const validationErrors = validateInvitePayload(input)
  if (Object.keys(validationErrors).length > 0) {
    return {
      error: {
        code: 'VALIDATION_FAILED',
        message: Object.values(validationErrors).join('; '),
      },
    }
  }

  const mobile = normalizeMobile(input.mobile)
  const { data, error } = await supabase.rpc('invite_staff', {
    email: input.email.trim().toLowerCase(),
    full_name: input.full_name.trim(),
    mobile,
    role: input.role,
    branch_ids: input.branch_ids,
    title: input.title ?? null,
  })

  if (error) return { error: mapError(error) }

  const id = data as string
  const { data: inv, error: fetchErr } = await supabase
    .from('staff_invitations')
    .select('*')
    .eq('id', id)
    .single()

  if (fetchErr) return { invitation: null, error: mapError(fetchErr) }
  return { invitation: inv as StaffInvitation, error: null }
}

/**
 * List all active (pending, non-revoked) invitations. Visible to
 * admins and branch managers; each sees only their own invitations
 * (enforced via RLS on `staff_invitations`).
 */
export async function listInvitations(): Promise<InvitationListResult> {
  const { data, error } = await supabase
    .from('staff_invitations')
    .select('*')
    .order('created_at', { ascending: false })

  if (error) return { invitations: [], error: mapError(error) }
  return { invitations: (data as StaffInvitation[]) ?? [], error: null }
}

/** Revoke an invitation (admin / inviting branch-manager, SRS §27.1.5). */
export async function revokeInvitation(invitationId: string): Promise<Result> {
  const { error } = await supabase.rpc('revoke_invitation', {
    invitation_id: invitationId,
  })
  if (error) return { error: mapError(error) }
  return { error: null }
}

/**
 * Accept an invitation. The RPC is SECURITY DEFINER and resolves
 * the user from the JWT; `code` is the 12-char code from the
 * invite email (SRS §27.1.4).
 */
export async function acceptInvitation(code: string): Promise<Result> {
  const { data: userResp } = await supabase.auth.getUser()
  const userId = userResp.user?.id
  if (!userId) {
    return { error: { code: 'NOT_AUTHENTICATED', message: 'You must be signed in' } }
  }

  const { error } = await supabase.rpc('accept_invitation', {
    code,
    user_id: userId,
  })
  if (error) return { error: mapError(error) }
  return { error: null }
}