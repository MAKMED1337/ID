#!/usr/bin/env bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SQL="${SCRIPT_DIR}/FillTable/"

function add() {
    echo "Inserting $1"
    docker compose -f docker-compose-dev.yml exec -T -it db psql -Uadmin -dID < "${SQL}/$1.sql"
}

add "people"

add "accounts"
add "countries"
add "cities"
add "offices"
add "document_types"
add "offices_kinds"
add "office_kinds_documents"
add "offices_kinds_relations"
add "administrators"

# add "death_certificates"
# add "birth_certificates"

# add "drivers_licences"
# add "educational_instances_types"
# add "educational_instances"
# add "educational_certificates_types"
# add "educational_certificates"
#
add "marriages"
