#!/usr/bin/env bash

VERSION=$1; shift

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ "$VERSION" == "v1" ]]; then
  echo "Checking for version: ${VERSION}"

  EXPECTED_HELM_CONTROLLER_VERSION="v0.31.2"
  EXPECTED_IMAGE_AUTOMATION_CONTROLLER_VERSION="v0.31.0"
  EXPECTED_IMAGE_REFLECTOR_CONTROLLER_VERSION="v0.26.1"
  EXPECTED_KUSTOMIZE_CONTROLLER_VERSION="v0.35.1"
  EXPECTED_NOTIFICATION_CONTROLLER_VERSION="v0.33.0"
  EXPECTED_SOURCE_CONTROLLER_VERSION="v0.36.1"

  EXPECTED_GITREPO_API_VERSION="source.toolkit.fluxcd.io/v1beta2"
  EXPECTED_KUSTOMIZATION_API_VERSION="kustomize.toolkit.fluxcd.io/v1beta2"
elif [[ "$VERSION" == "v2" ]]; then
  echo "Checking for version: ${VERSION}"

  EXPECTED_HELM_CONTROLLER_VERSION="v0.35.0"
  EXPECTED_IMAGE_AUTOMATION_CONTROLLER_VERSION="v0.35.0"
  EXPECTED_IMAGE_REFLECTOR_CONTROLLER_VERSION="v0.29.1"
  EXPECTED_KUSTOMIZE_CONTROLLER_VERSION="v1.0.1"
  EXPECTED_NOTIFICATION_CONTROLLER_VERSION="v1.0.0"
  EXPECTED_SOURCE_CONTROLLER_VERSION="v1.0.1"

  EXPECTED_GITREPO_API_VERSION="source.toolkit.fluxcd.io/v1"
  EXPECTED_KUSTOMIZATION_API_VERSION="kustomize.toolkit.fluxcd.io/v1"
else
  echo "Unknown version! Either pass 'v1' or 'v2'!"
  exit 1
fi

function check_controller_version() {
  namespace="$1"; shift
  label="$1"; shift
  expected_version="$1"; shift

  echo "## Checking for pod in '${namespace}' with label '${label}'..."

  actual_image="$(kubectl -n "${namespace}" get pod -l "${label}" -o yaml | yq '.items[].spec.containers[].image')"
  actual_tag="$(echo "$actual_image" | cut -d ":" -f 2)"

  if [[ "${actual_tag}" == "${expected_version}" ]]; then
    echo -e "  > ${GREEN}Passed!${NC} (Expected: '${expected_version}' and got: '${actual_tag}')"
  else
    echo -e "  > ${RED}Failed!${NC} Pod in '${namespace}' with label '${label}' does not match expected version: '${expected_version}', but was: '${actual_tag}'!"
  fi
}

echo ""
echo "# Checking: 'flux-giantswarm' pods..."
echo ""

kubectl get pods -n "flux-giantswarm" --no-headers
echo ""

check_controller_version "flux-giantswarm" "app=helm-controller" "${EXPECTED_HELM_CONTROLLER_VERSION}"
check_controller_version "flux-giantswarm" "app=image-automation-controller" "${EXPECTED_IMAGE_AUTOMATION_CONTROLLER_VERSION}"
check_controller_version "flux-giantswarm" "app=image-reflector-controller" "${EXPECTED_IMAGE_REFLECTOR_CONTROLLER_VERSION}"
check_controller_version "flux-giantswarm" "app=kustomize-controller" "${EXPECTED_KUSTOMIZE_CONTROLLER_VERSION}"
check_controller_version "flux-giantswarm" "app=notification-controller" "${EXPECTED_NOTIFICATION_CONTROLLER_VERSION}"
check_controller_version "flux-giantswarm" "app=source-controller" "${EXPECTED_SOURCE_CONTROLLER_VERSION}"

echo ""
echo "# Checking Flux git repositories in 'flux-giantswarm' for API version of '${EXPECTED_GITREPO_API_VERSION}'..."
echo ""

#IFS=$'\n'
#for gitrepo in $(kubectl get gitrepositories -A -o custom-columns="NAMESPACE":.metadata.namespace,"NAME":.metadata.name,"STATUS":'.status.conditions[].type',"KIND":.kind,"APIVERSION":.apiVersion --no-headers); do
#  if [[ "${gitrepo}" == *${EXPECTED_GITREPO_API_VERSION} ]]
#    then
#      echo -e "${GREEN}${gitrepo}${NC}";
#    else
#      echo -e "${RED}${gitrepo}${NC}";
#    fi
#done

echo ""
echo "# Checking Flux kustomizations in 'flux-giantswarm' for API version of '${EXPECTED_KUSTOMIZATION_API_VERSION}'..."
echo ""

IFS=$'\n'
for ks in $(kubectl get kustomizations -A -o custom-columns="NAMESPACE":.metadata.namespace,"NAME":.metadata.name,"STATUS":'.status.conditions[].type',"KIND":.kind,"APIVERSION":.apiVersion --no-headers); do
  if [[ "${ks}" == *${EXPECTED_KUSTOMIZATION_API_VERSION} ]]
  then
    echo -e "${GREEN}${ks}${NC}";
  else
    echo -e "${RED}${ks}${NC}";
  fi
done

echo ""
echo "# Checking: 'flux-system' pods..."
echo ""

kubectl get pods -n "flux-system" --no-headers
echo ""

check_controller_version "flux-system" "app=helm-controller" "${EXPECTED_HELM_CONTROLLER_VERSION}"
check_controller_version "flux-system" "app=image-automation-controller" "${EXPECTED_IMAGE_AUTOMATION_CONTROLLER_VERSION}"
check_controller_version "flux-system" "app=image-reflector-controller" "${EXPECTED_IMAGE_REFLECTOR_CONTROLLER_VERSION}"
check_controller_version "flux-system" "app=kustomize-controller" "${EXPECTED_KUSTOMIZE_CONTROLLER_VERSION}"
check_controller_version "flux-system" "app=notification-controller" "${EXPECTED_NOTIFICATION_CONTROLLER_VERSION}"
check_controller_version "flux-system" "app=source-controller" "${EXPECTED_SOURCE_CONTROLLER_VERSION}"
