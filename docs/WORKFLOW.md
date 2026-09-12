# Workflow & Branch Conventions

Applies to every task in the MVP breakdown (`docs/PROJECT_TASKS_BREAKDOWN.md`, §3).

## Rules

1. **One task = one thread.** Each task is worked in its own chat thread.
2. **Branch per task.** Branch name: `task/TXX-short-slug`
   (e.g. `task/T02-repo-structure-pages-deploy`). Open a PR into `main`,
   get it merged, then move to the next task.
3. **Dependency rule.** Before starting a task, every item in its
   **Dependencies** must be :green_circle: Done. If not, state
   *"I will not start this task until [TXX] is complete."* and wait.
4. **Status values** are updated in the plan's Status column:

   | Status | Meaning |
   | ------ | ------- |
   | :white_large_square: Not Started | Ready to be picked up (dependencies done) |
   | :yellow_circle: Needs Input | Blocked waiting on data/decision |
   | :large_blue_circle: In Progress | Currently being worked on |
   | :green_circle: Done | Merged via PR and verified |

5. **Hand-off tasks (P1 + P2).** Backend PR first, then the UI PR. The
   backend part must be merged before the UI part starts.
6. **Verification.** A task is `Done` only after its PR is merged AND its
   acceptance criteria pass in the live build.
7. **Open items (T35).** Client-data decisions are tracked there. Blocked
   tasks become `Needs Input` with a note.

## Pull Requests

- Title: `TXX — short description`
- Branch: `task/TXX-short-slug`
- Base: `main`
- Fill in the PR template (`.github/pull_request_template.md`): what was
  done, how it was verified, acceptance criteria status.
- Never commit `.env` files or real secrets (see `.env.example`).

## Verification before merging (T2 baseline)

```bash
cd web
npm ci
npm run typecheck
npm run build
# Local preview of the deployed output:
npm run preview
```

The `main` branch auto-deploys to
`https://yahiaAlhindi.github.io/The-Perfect-Look-/` via
`.github/workflows/deploy.yml`.