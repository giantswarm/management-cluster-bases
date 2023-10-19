#!/usr/bin/env bash

SCRIPT_PATH="$(cd -- "$(dirname "$0")" > /dev/null 2>&1 || exit ; pwd -P)"

virtualenv -p python3 "${SCRIPT_PATH}/virtualenv"

source "${SCRIPT_PATH}/virtualenv/bin/activate"

"${SCRIPT_PATH}"/virtualenv/bin/pip install -r "${SCRIPT_PATH}/requirements.txt"
