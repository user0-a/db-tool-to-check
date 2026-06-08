# sample-app

An example target repository for testing **jazda-tool**. It's a minimal Spring
Boot (Maven) app that contains the three things the tool cares about:

- `migrations/` — Flyway-style `V<6-digit>_<name>.sql` files (append-only history)
- `migration-rollback/` — holds a single rollback script
- `pvt` — a file the feature branch always owns

The Spring Boot app itself is trivial (a `/` endpoint); it exists so the repo is
a real, buildable Java project. The migration files are not wired into a running
Flyway/DB — they're here purely as the artifacts the tool manipulates.

## Quick test (no GitHub required)

`setup-test-repo.sh` builds a self-contained git playground with a local **bare
repo as the remote**, so you can exercise the whole tool without touching GitHub.

```bash
./setup-test-repo.sh                 # builds ~/Desktop/jazda-playground
# or choose a location:
./setup-test-repo.sh /tmp/jazda-playground
```

It creates a common base, then diverges:

| Branch | migrations | rollback | pvt |
|--------|-----------|----------|-----|
| `main` | V1, V2, V3_add_orders, V4_add_payments, V5_add_audit | V5_add_audit | MAIN |
| `feature/products` | V1, V2, V3_add_products | V3_add_products | FEATURE |

Then point the tool at the clone it produced:

```bash
cd <your jazda-tool folder>
export GIT_REPO_PATH=~/Desktop/jazda-playground/clone
export GIT_USERNAME=ignored      # local remote ignores credentials
export GIT_TOKEN=ignored
mvn spring-boot:run
```

```bash
curl -s -X POST http://localhost:8080/api/merge \
  -H "Content-Type: application/json" \
  -d '{"branch":"feature/products"}'
```

## Expected result

After the tool runs, check out `feature/products` in the clone:

- `migrations/` keeps main's history untouched and the feature's migration is
  renumbered to **maxMain + 1 = 6**:
  `V000001`, `V000002`, `V000003_add_orders`, `V000004_add_payments`,
  `V000005_add_audit`, **`V000006_add_products`**
- `migration-rollback/` contains **only** `V000006_add_products.sql`
- `pvt` is the **FEATURE** version

What makes this a good test: git only reports a real conflict on `pvt`. The
migration and rollback files have different names on each branch, so they merge
with no conflict — proving the renumber/rollback logic runs as post-merge
normalization, not conflict resolution.

## Re-running

The script wipes and rebuilds the playground each time, so just run it again to
reset to a clean starting state.
