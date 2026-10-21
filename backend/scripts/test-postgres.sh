#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for binary in initdb pg_ctl createdb; do
  command -v "$binary" >/dev/null || { echo "Install PostgreSQL binaries to run SQL integration tests" >&2; exit 1; }
done
mkdir -p .local
cluster_dir=$(mktemp -d "$PWD/.local/test-pg.XXXXXX")
test_port=${TEST_POSTGRES_PORT:-55440}
cleanup() {
  pg_ctl -D "$cluster_dir" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$cluster_dir"
}
trap cleanup EXIT
initdb -D "$cluster_dir" -A trust -U gymmane_test >/dev/null
pg_ctl -D "$cluster_dir" -l "$cluster_dir/server.log" -o "-h 127.0.0.1 -p $test_port" start >/dev/null
createdb -h 127.0.0.1 -p "$test_port" -U gymmane_test gymmane_test
export TEST_DATABASE_URL="postgres://gymmane_test@127.0.0.1:$test_port/gymmane_test"
if (( $# )); then
  "$@"
else
  npm test
fi
