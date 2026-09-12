# Workflow and Branch Conventions

This workflow applies to the tasks in
docs/PROJECT_TASKS_BREAKDOWN.md (SRS v2).

## Rules

1. One task = one focused thread.
2. Use one branch per task:
   task/TXX-short-slug
3. Open a PR into main, verify the acceptance criteria, and merge before
   starting dependent work.
4. Before starting a task, check every dependency in the task plan. If
   any dependency is not Done, state:
   "I will not start this task until [TXX] is complete."
   Do not implement the blocked task.
5. Status values:

   | Status | Meaning |
   | --- | --- |
   | Not Started | Work has not begun |
   | Needs Input | Waiting for client, clinic, provider, or policy input |
   | In Progress | Actively being worked on |
   | Done | PR merged and acceptance criteria verified |

6. P1 + P2 hand-off tasks require the backend/API PR first, followed by
   the web/mobile consumer PR.
7. Demo defaults must be labelled and must not become production policy
   without client approval.
8. T35 is the decision gate for clinic policies, payment provider,
   subscription plans, nutrition formulas, legal text, and release scope.
   T36 is the gate for the client website, service catalogue, and brand
   assets.

## Pull requests

- Title: TXX - short description
- Branch: task/TXX-short-slug
- Base: main
- Include what changed, how it was verified, and the status of each
  acceptance criterion.
- Never commit .env files, service-role keys, payment secrets, or real
  customer/health data.

## Verification baseline

From the web directory:

    npm ci
    npm run typecheck
    npm run build
    npm run preview

For database changes, also run the relevant SQL/RLS tests and migration
checks. For payment/subscription changes, use provider sandbox events and
verify replay/idempotency. For nutrition changes, run approved fixture
calculations and confirm formula/version metadata.

The main branch deploys the web/PWA build through the configured GitHub
Actions workflow. Native mobile release and production payment credentials
are tracked by T45 and T48 and require the relevant client approvals.
