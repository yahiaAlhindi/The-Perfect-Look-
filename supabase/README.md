# supabase/

Supabase schema source of truth for The Perfect Look.

- `migrations/` — SQL migrations, applied in filename order (e.g.
  `001_...sql`). Written in task T3 (schema) and T4 (seed data).
- `seed.sql` — idempotent demo seed (services, staff, settings).

## Applying locally

```bash
supabase db push        # remote
supabase db reset       # local (after: supabase start)
```

> Only the Supabase URL + **anon** key ever reach the browser. The
> service-role key is used exclusively by `tools/` (T25) and CI.