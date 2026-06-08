#!/usr/bin/env bash
#
# Builds a self-contained git playground to test jazda-tool, with NO GitHub needed.
#
#   playground/
#     origin.git   <- bare repo acting as "GitHub" (the remote)
#     clone/       <- the working clone -> point GIT_REPO_PATH at this
#
# It creates a common base, then diverges:
#   main             : migrations V1,V2 + V3_add_orders, V4_add_payments, V5_add_audit
#                      rollback -> V5_add_audit ; pvt -> "MAIN"
#   feature/products : migrations V1,V2 + V3_add_products
#                      rollback -> V3_add_products ; pvt -> "FEATURE"
#
# After running jazda-tool on branch "feature/products" you should see:
#   - migrations/ : V1,V2,V3_add_orders,V4_add_payments,V5_add_audit (main's, untouched)
#                   + V000006_add_products.sql  (feature's, renumbered to maxMain+1 = 6)
#   - migration-rollback/ : ONLY V000006_add_products.sql
#   - pvt : the FEATURE version
#
set -euo pipefail

SKELETON="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$HOME/Desktop/jazda-playground}"
ORIGIN="$ROOT/origin.git"
CLONE="$ROOT/clone"
BUILD="$ROOT/.build"

GIT="git -c user.email=test@example.com -c user.name=Tester -c init.defaultBranch=main -c commit.gpgsign=false"

echo ">> Resetting playground at $ROOT"
rm -rf "$ROOT"
mkdir -p "$ROOT"

# ---------------------------------------------------------------------------
# 1. Base commit (common ancestor) from the skeleton in this folder
# ---------------------------------------------------------------------------
mkdir -p "$BUILD"
cp -R "$SKELETON/." "$BUILD/"
rm -f "$BUILD/setup-test-repo.sh"   # don't commit the script into the repo
rm -rf "$BUILD/target" "$BUILD/.git"

cd "$BUILD"
$GIT init -q
$GIT add .
$GIT commit -qm "Base: skeleton + migrations V1,V2 (rollback V2), pvt base"

# ---------------------------------------------------------------------------
# 2. feature/products branches from the base
# ---------------------------------------------------------------------------
$GIT branch feature/products

# ---------------------------------------------------------------------------
# 3. Advance main
# ---------------------------------------------------------------------------
cat > migrations/V000003_add_orders.sql <<'SQL'
-- V000003_add_orders.sql
CREATE TABLE orders (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL);
SQL
cat > migrations/V000004_add_payments.sql <<'SQL'
-- V000004_add_payments.sql
CREATE TABLE payments (id BIGINT PRIMARY KEY, order_id BIGINT NOT NULL, amount NUMERIC(12,2));
SQL
cat > migrations/V000005_add_audit.sql <<'SQL'
-- V000005_add_audit.sql
CREATE TABLE audit_log (id BIGINT PRIMARY KEY, message VARCHAR(500));
SQL
$GIT rm -q migration-rollback/V000002_create_users.sql
mkdir -p migration-rollback
cat > migration-rollback/V000005_add_audit.sql <<'SQL'
-- rollback for V000005_add_audit.sql
DROP TABLE audit_log;
SQL
printf 'pvt: MAIN version (should be discarded by the tool)\n' > pvt
$GIT add -A
$GIT commit -qm "main: add migrations V3,V4,V5; rollback -> V5; change pvt"

# ---------------------------------------------------------------------------
# 4. Advance feature/products (note: number 3 collides numerically with main,
#    but different name -> different path -> NO git conflict in migrations/)
# ---------------------------------------------------------------------------
$GIT checkout -q feature/products
cat > migrations/V000003_add_products.sql <<'SQL'
-- V000003_add_products.sql
CREATE TABLE products (id BIGINT PRIMARY KEY, name VARCHAR(255) NOT NULL);
SQL
$GIT rm -q migration-rollback/V000002_create_users.sql
mkdir -p migration-rollback
cat > migration-rollback/V000003_add_products.sql <<'SQL'
-- rollback for V000003_add_products.sql
DROP TABLE products;
SQL
printf 'pvt: FEATURE version (this is the one that must survive)\n' > pvt
$GIT add -A
$GIT commit -qm "feature/products: add V000003_add_products; rollback; change pvt"

# ---------------------------------------------------------------------------
# 5. Bare "origin" + push both branches
# ---------------------------------------------------------------------------
$GIT init -q --bare "$ORIGIN"
$GIT remote add origin "$ORIGIN"
$GIT push -q origin main feature/products

# ---------------------------------------------------------------------------
# 6. Fresh clone for the tool, and clean up the build dir
# ---------------------------------------------------------------------------
cd "$ROOT"
$GIT clone -q "$ORIGIN" "$CLONE"
rm -rf "$BUILD"

cat <<EOF

Playground ready.

  Remote (bare "GitHub"): $ORIGIN
  Clone for the tool:     $CLONE

Run the tool against it (no real token needed for a local remote):

  cd <your jazda-tool folder>
  export GIT_REPO_PATH="$CLONE"
  export GIT_USERNAME=ignored
  export GIT_TOKEN=ignored
  mvn spring-boot:run

Then in another terminal:

  curl -s -X POST http://localhost:8080/api/merge \\
    -H "Content-Type: application/json" \\
    -d '{"branch":"feature/products"}' | jq .

Verify the result on the feature branch:

  cd "$CLONE"
  git checkout feature/products && git pull -q
  ls migrations            # expect V1,V2,V3_add_orders,V4_add_payments,V5_add_audit,V000006_add_products
  ls migration-rollback    # expect ONLY V000006_add_products.sql
  cat pvt                  # expect the FEATURE version
EOF
