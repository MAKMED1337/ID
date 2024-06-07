#!/usr/bin/env bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

g++ -o "${SCRIPT_DIR}/main" "${SCRIPT_DIR}/script.cpp" && "${SCRIPT_DIR}/main"
