#!/usr/bin/env bash

PASSWORD_PROM=$(cat /dev/urandom | env LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
PASSWORD_ADMIN=$(cat /dev/urandom | env LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)

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
        $(htpasswd -bBn prom "${PASSWORD_PROM}")
        $(htpasswd -bBn admin "${PASSWORD_ADMIN}")
      credentials: |-
        {}
    serviceMonitor:
      basicAuth:
        username: prom
        password: ${PASSWORD_PROM}
  adminPassword: ${PASSWORD_ADMIN}

EOF
