#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

for filename in "${SCRIPT_DIR}/generator"/*.sql; do
    echo "Inserting data from ${filename}"
    docker compose -f docker-compose-dev.yml exec -T -it db psql -Uadmin -dID < "${filename}"
done
