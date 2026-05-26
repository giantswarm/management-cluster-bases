# Agentic Platform Extras

This directory contains the Flux resources required to deploy the
`agentic-platform` umbrella chart on a Giant Swarm management cluster.

## Overview

`agentic-platform` is a Helm umbrella that bundles three sub-charts behind a
single release:

- **muster** — MCP aggregator / OAuth resource server
- **agentgateway** — MCP data plane (controller + dynamically-rendered
  data-plane pod via `AgentgatewayParameters`)
- **valkey** — `giantswarm/valkey-app` for muster's OAuth session storage

It replaces the standalone `extras/muster` base. The umbrella owns the
`Gateway` (data-plane spawn trigger), `AgentgatewayParameters`, and the
CiliumNetworkPolicies wiring the controller and data plane.

## Prerequisites

The umbrella does **not** ship the agentgateway CRDs — they're a cluster
prerequisite:

```
helm install agentgateway-crds \
  oci://cr.agentgateway.dev/charts/agentgateway-crds --version v1.2.1 \
  -n muster --create-namespace
```

Muster's CRDs (`MCPServer`, `ServiceClass`, `Workflow`) ship inside the
umbrella via the muster sub-chart's `templates/crds.yaml`. Remove any
standalone references to `giantswarm/muster/v*/helm/muster/crds/*.yaml`
from the cluster's `crds/kustomization.yaml`.

## Configuration

Configuration is supplied via two ConfigMaps merged onto the HelmRelease:

1. **shared-configs** rendered into `agentic-platform-konfiguration` by the
   bundled `Konfiguration` resource. Requires a matching `agentic-platform`
   template in `giantswarm-config` that renders values under the umbrella's
   `muster:` subchart prefix (e.g. `muster.muster.oauth.server.baseUrl`).
2. **per-cluster overrides** via a `agentic-platform-user-values` ConfigMap
   appended by the consumer kustomization (see usage below).

Required per-cluster fields (template-time fail-guards reject install
otherwise):

| Field | Notes |
|---|---|
| `muster.muster.oauth.server.baseUrl` | Public muster URL (HTTPS) |
| `muster.muster.oauth.server.dex.issuerUrl` | Dex issuer on this cluster |
| `muster.muster.oauth.server.dex.clientId` | OAuth client pre-registered in Dex |
| `muster.muster.oauth.server.existingSecret` | Secret with `dex-client-secret`, `registration-token`, `oauth-encryption-key`, `valkey-password` |
| `muster.muster.gatewayAPI.httpRoute.parentRefs` | Public Gateway to attach to (e.g. `envoy-gateway-system/giantswarm-default`) |
| `muster.muster.gatewayAPI.httpRoute.hostnames` | Public hostnames |
| `valkey.valkey.auth.usersExistingSecret` | Conventionally the same Secret as above (key `valkey-password`) |

## Secrets Required

Before deployment, ensure this Secret exists in the `muster` namespace
(conventionally a single Secret referenced from both `muster.muster.oauth.server.existingSecret`
and `valkey.valkey.auth.usersExistingSecret`):

```bash
kubectl create secret generic agentic-platform-secrets \
  --namespace muster \
  --from-literal=dex-client-secret=<dex-client-secret> \
  --from-literal=registration-token=$(openssl rand -hex 32) \
  --from-literal=oauth-encryption-key=$(openssl rand -base64 32) \
  --from-literal=valkey-password=$(openssl rand -base64 32)
```

## Usage

To deploy on a management cluster, reference this directory from
`giantswarm-management-clusters`:

```yaml
# management-clusters/<mc>/extras/agentic-platform/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/agentic-platform?ref=main
  - agentic-platform-secrets.enc.yaml
  - ./mcpservers
  - ./secrets
generatorOptions:
  disableNameSuffixHash: true
configMapGenerator:
  - name: agentic-platform-user-values
    namespace: flux-giantswarm
    files:
      - values=user-values.yaml
patches:
  - patch: |-
      - op: add
        path: /spec/valuesFrom/-
        value:
          kind: ConfigMap
          name: agentic-platform-user-values
          valuesKey: values
    target:
      kind: HelmRelease
      name: agentic-platform
```

## Dependencies

- dex-app >= 2.1.5 (for muster static client support)
- agentgateway-crds chart pre-installed
- shared-configs with an `agentic-platform` app template (renders values
  under the `muster:` umbrella prefix)

## Related

- [agentic-platform chart](https://github.com/giantswarm/agentic-platform)
- [Muster MC Deployment Concept](https://github.com/giantswarm/muster/blob/main/docs/concepts/mc-deployment.md)
