# The-Perfect-Look-

Multi-branch health, beauty, booking, payments, and wellness platform for
The Perfect Look clinic.

| Path        | Purpose                                              |
| ----------- | ---------------------------------------------------- |
| `web/`      | Frontend app — React + Vite + TypeScript (+ Tailwind in T1) |
| `supabase/` | Database schema — SQL migrations + seed               |
| `tools/`    | Server-side utilities (Excel migration tool, T25)     |
| `docs/`     | This plan + workflow/deployment docs                  |

## Live site

<https://yahiaAlhindi.github.io/The-Perfect-Look-/>

## Getting started (frontend)

```bash
cd web
npm ci
npm run dev      # http://localhost:5173/The-Perfect-Look-/
```

```bash
npm run typecheck
npm run build
npm run preview
```

Env vars: copy `web/.env.example` → `web/.env` and fill in the Supabase
project values (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`). Never
commit real keys; the complete reference is `.env.example`.

## Docs

- [Software requirements specification](docs/The_Perfect_Look_App_Requirements_UPDATED.md)
- [Task plan](docs/PROJECT_TASKS_BREAKDOWN.md)
- [Branch & PR conventions](docs/WORKFLOW.md)
- [Deployment pipeline](docs/DEPLOYMENT.md)

## Branch & PR conventions

One task = one branch (`task/TXX-short-slug`) → PR into `main` →
auto-deploy. Details in `docs/WORKFLOW.md`. `main` deploys on every merge.
