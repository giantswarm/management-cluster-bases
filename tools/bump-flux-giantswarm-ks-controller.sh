#!/usr/bin/env bash

current_image=$(kubectl -n flux-giantswarm get deployment kustomize-controller -o yaml | yq '.spec.template.spec.containers[] | select(.name == "manager") | .image')

echo "Current image is: ${current_image}"

current_image_without_tag=$(echo "${current_image}" | cut -d ":" -f 1)

echo "Image without tag: ${current_image_without_tag}"

new_image="${current_image_without_tag}:v1.0.1"

echo ""
echo "New image: ${new_image}"

echo ""
echo "Updating..."

kubectl -n flux-giantswarm set image deployment/kustomize-controller manager="${new_image}" ensure-sopsenv="${new_image}"

echo ""
echo "All done! :)"

echo ""
echo "Let's watch the pods if all is good:"
echo ""

kubectl -n flux-giantswarm get pods -w
