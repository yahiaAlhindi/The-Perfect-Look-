# tools/

Server-side / one-time utility scripts. Owned by P1.

Current layout is a placeholder — planned tasks that land here:

- **T25 — Excel migration tool.** Node/TS + SheetJS to read the legacy
  Excel and migrate into Supabase (dry-run mode first). Uses the
  service-role key from env, never the browser.
- **T31 — security/reporting helpers** as needed.

## Conventions

- Scripts are Node + TypeScript, run via this directory.
- Service-role keys come from environment variables (see `.env.example`);
  they are never committed and never shipped to the browser.