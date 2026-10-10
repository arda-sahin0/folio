set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
    set -a
    source <(tr -d '\r' < .env)
    set +a
fi

read -r -a PSQL <<< "${PSQL:-docker compose exec -T db psql -U ${POSTGRES_USER:-folio} -d ${POSTGRES_DB:-folio}}"

run() {
    echo "  $1"
    "${PSQL[@]}" -X -q -v ON_ERROR_STOP=1 < "$1" > /dev/null
}

run_test() {
    echo "  $1"
    cat tests/helpers.sql "$1" | "${PSQL[@]}" -X -q -v ON_ERROR_STOP=1 > /dev/null
}

echo "Migrations"
for f in migrations/*.sql; do
    run "$f"
    "${PSQL[@]}" -X -q -v ON_ERROR_STOP=1 \
        -c "INSERT INTO schema_migrations (filename) VALUES ('$(basename "$f")') ON CONFLICT DO NOTHING"
done

echo "Load 1"
for f in loaders/*.sql; do run "$f"; done
run tests/snapshot.sql

echo "Load 2"
for f in loaders/*.sql; do run "$f"; done

echo "Tests"
for f in tests/test_*.sql; do run_test "$f"; done

echo "Queries"
for f in queries/m*/*.sql; do run "$f"; done

echo "All checks passed."
