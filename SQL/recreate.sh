#!/usr/bin/env bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

"${SCRIPT_DIR}/merge.sh"
cd "${SCRIPT_DIR}/FillTable"
./run.sh
cd "${SCRIPT_DIR}/.."
docker compose -f docker-compose-dev.yml exec -it -T db psql -Uadmin -dID < "${SCRIPT_DIR}/clear.sql"
docker compose -f docker-compose-dev.yml exec -it -T db psql -Uadmin -dID < "${SCRIPT_DIR}/create_all.sql"
"${SCRIPT_DIR}/inserter.sh"
