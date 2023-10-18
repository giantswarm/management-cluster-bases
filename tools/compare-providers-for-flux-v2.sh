#!/usr/bin/env bash

if [[ $(kustomize version) != "v5.0.3" ]]; then
  echo "Please use kustomize version 5.0.3!"
  echo "See: https://github.com/fluxcd/kustomize-controller/blob/v1.0.1/CHANGELOG.md#100-rc4"
  exit 1
fi

SCRIPT_PATH="$(cd -- "$(dirname "$0")" > /dev/null 2>&1 || exit ; pwd -P)"
REPOSITORY_ROOT=$(cd "${SCRIPT_PATH}/.." > /dev/null 2>&1 || exit ; pwd -P)

OUTPUT_DIR="${REPOSITORY_ROOT}/output"

echo "$SCRIPT_PATH"
echo "$REPOSITORY_ROOT"

# shellcheck disable=SC2010
PROVIDER_BASES=$(ls "${REPOSITORY_ROOT}/bases/provider" | grep -v "^eks$")

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

for provider_base in ${PROVIDER_BASES}; do
  echo "# Running for provider base: ${provider_base}"
  echo ""

  target_dir="${OUTPUT_DIR}/${provider_base}"

  mkdir -p "${target_dir}"

  echo "- Flux V1 Build ---------------------------------------------------------"
  kustomize build --load-restrictor LoadRestrictionsNone --enable-helm "${REPOSITORY_ROOT}/bases/provider/${provider_base}" > "${target_dir}/flux-v1.yaml"
  echo ""

  echo "- Flux V2 Build ---------------------------------------------------------"
  kustomize build --load-restrictor LoadRestrictionsNone --enable-helm "${REPOSITORY_ROOT}/bases/provider/${provider_base}/flux-v2" > "${target_dir}/flux-v2.yaml"
  echo ""

  echo "Generating diff..."
  diff "${target_dir}/flux-v1.yaml" "${target_dir}/flux-v2.yaml" > "${target_dir}/diff-v1-to-v2.txt"
  echo ""

  echo "========================================================================="
  echo ""
done
