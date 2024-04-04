#!/usr/bin/env bash

WORKDIR=$(mktemp -d)
read -p "Enter a password for the prom user: " PASSWORD_PROM
htpasswd -b -c "${WORKDIR}/prom" prom "${PASSWORD_PROM}"
read -p "Enter a password for the admin user: " PASSWORD_ADMIN
htpasswd -b -c "${WORKDIR}/admin" admin "${PASSWORD_ADMIN}"

cat "${WORKDIR}/prom" > "${WORKDIR}/passwords"
cat "${WORKDIR}/admin" >> "${WORKDIR}/passwords"

AUTH_HEADER=$(cat "${WORKDIR}/admin" | base64)
>&2 printf "This is a secret snippet that you can add to zot:\n\n"

cat << EOF
apiVersion: v1
kind: Secret
metadata:
  name: zot-secret-values
stringData:
  values.yaml: |-
    mountSecret: true
    secretFiles: 
      htpasswd: |-
$(cat "${WORKDIR}/passwords" | sed 's/^/        /')
    authHeader: ${AUTH_HEADER}
    serviceMonitor:
      basicAuth:
        username: prom
        password: ${PASSWORD_PROM}
  # Here stored the admin password, so it's possible to find it,
  # since it's not saved anywhere
  adminPassword: ${PASSWORD_ADMIN}

EOF

