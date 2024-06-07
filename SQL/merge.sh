#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cat "${SCRIPT_DIR}/create.sql" "${SCRIPT_DIR}/functions.sql" "${SCRIPT_DIR}/triggers.sql" "${SCRIPT_DIR}/views.sql" > "${SCRIPT_DIR}/create_all.sql"
