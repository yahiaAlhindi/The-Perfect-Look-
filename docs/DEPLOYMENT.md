# GitHub Pages Deployment (T2)

Live URL: <https://yahiaAlhindi.github.io/The-Perfect-Look-/>

Pipeline: `.github/workflows/deploy.yml` runs on every push to `main`
(and via `workflow_dispatch`). It installs, typechecks, builds `web/`, and
publishes `web/dist` to GitHub Pages using the official
`actions/deploy-pages` action.

## One-time repository setup

Enable Pages for the repo:

1. GitHub → repo → **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**
   (do NOT pick a branch — the workflow publishes the artifact itself).
3. Optional but recommended: add the `github-pages`
   [environment](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
   Evironment protection rules (the workflow already declares it).

No secrets are required: Pages deployment uses the built-in
`id-token` / `pages` permissions.

## Strategy

- **Base path:** `vite.config.ts` sets `base: '/The-Perfect-Look-/'` to
  match the sub-path URL. Keep it in sync with the repo name.
- **PWA:** `vite-plugin-pwa` is configured for readiness (manifest +
  service worker). Full install/offline polish is task T30.
- **Secrets:** only public Supabase *anon* URL/key are ever compiled into
  the frontend (via `VITE_*` env vars). The service-role key stays
  server-side (`tools/`) and is never committed — see `.env.example`.

## Verifying a deployment

1. Merge a PR into `main`.
2. Watch **Actions** → **Deploy to GitHub Pages** → `deploy` job.
3. Open `https://yahiaAlhindi.github.io/The-Perfect-Look-/`.
4. Confirm the service worker + manifest serve from the sub-path.