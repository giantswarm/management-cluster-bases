#!/usr/bin/env bash

WORKDIR=$(mktemp -d)
read -p "Enter a password for the prom user: " PASSWORD_PROM
htpasswd -bBn prom "${PASSWORD_PROM}" > "${WORKDIR}/prom"
read -p "Enter a password for the admin user: " PASSWORD_ADMIN
htpasswd -bBn admin "${PASSWORD_ADMIN}" > "${WORKDIR}/admin"

cat "${WORKDIR}/prom" > "${WORKDIR}/passwords"
cat "${WORKDIR}/admin" >> "${WORKDIR}/passwords"

AUTH_HEADER=$(echo -n "admin:${PASSWORD_ADMIN}" | base64)
>&2 printf "This is a secret snippet that you can add to zot:\n\n"

cat << EOF
apiVersion: v1
kind: Secret
metadata:
  name: zot-secret-values
  namespace: flux-giantswarm
stringData:
  values.yaml: |-
    mountSecret: true
    secretFiles:
      htpasswd: |-
$(cat "${WORKDIR}/passwords" | sed 's/^/        /')
    serviceMonitor:
      basicAuth:
        username: prom
        password: ${PASSWORD_PROM}
  adminPassword: ${PASSWORD_ADMIN}

EOF
