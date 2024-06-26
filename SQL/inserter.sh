#!/usr/bin/env bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SQL="${SCRIPT_DIR}/FillTable/"
ID="${SCRIPT_DIR}/../"

function add() {
    echo "Inserting $1"
    docker compose -f "${ID}/docker-compose-dev.yml" exec -T -it db psql -Uadmin -dID < "${SQL}/$1.sql"
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

add "death_certificates"
add "birth_certificates"

add "drivers_licences"

add "educational_certificates_types"
add "educational_instances" #stores educational_instances_types_relation inserts
add "educational_certificates"

add "marriages"
add "marriage_certificates"
add "divorces"
add "divorce_certificates"

add "passports"

add "visa_categories"
add "international_passports"
add "visas"
add "pet_passports"