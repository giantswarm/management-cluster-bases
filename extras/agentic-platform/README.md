# Agentic Platform Extras

This directory contains the Flux resources required to deploy the
`agentic-platform` meta-package on a Giant Swarm management cluster.

## Overview

As of chart **v1.5.x** `agentic-platform` is a **meta-package (app-of-apps)**:
it no longer bundles sub-charts, but renders each component as its own Flux
`OCIRepository` + `HelmRelease` (version ranges resolved at reconcile time, so
component releases roll forward with no PR). Components include muster (MCP
aggregator / OAuth resource server), valkey (OAuth session storage),
agentgateway (MCP data plane), kagent, klaus-gateway, agent-sandbox, and the
`agentic-platform-connectivity` chart that owns the wiring (public `HTTPRoute`,
`Gateway`, `AgentgatewayParameters`, CiliumNetworkPolicies).

On Giant Swarm clusters the meta-package's `HelmRelease` sets:

```yaml
spec:
  values:
    gitops:
      namespace: flux-giantswarm      # render the child Flux CRs here — exempt
      targetNamespace: agentic-platform  #   from flux-multi-tenancy; workloads here
```

The child `HelmRelease`s are created in `flux-giantswarm` (the
flux-multi-tenancy Kyverno policy rejects HelmReleases lacking
`serviceAccountName` outside `flux-giantswarm`/`giantswarm`/`monitoring`) and
install their workloads into `agentic-platform`.

## Prerequisites

CRDs are **app-owned** (chart >= v1.10.0): each component ships its own CRDs in
the chart's `crds/` directory and the meta-package sets `crds: CreateReplace`
on the component, so the CRDs are installed and upgraded with the component
itself. There is no separate CRD bundle — the previous
`agentic-platform-crds` `HelmRelease` was retired on 2026-06-22 (its CRDs carry
`helm.sh/resource-policy: keep`, so removing the bundle leaves the live CRDs and
their CRs untouched). CR-before-CRD ordering is handled inside the child
releases: `agentic-platform-connectivity` and `agentic-platform-mcps`
`dependsOn` the CRD-owning components (`agentgateway`, `kagent`), so a CR is
never applied before its CRD exists. No manual `helm install` for CRDs is
required, and any standalone references to
`giantswarm/muster/v*/helm/muster/crds/*.yaml` should be removed from the
cluster's `crds/kustomization.yaml`.

The Gateway API v1 CRDs and a Gateway to attach muster's public `HTTPRoute` to
(e.g. `envoy-gateway-system/giantswarm-default`) remain cluster prerequisites.

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
  --namespace agentic-platform \
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
- Gateway API v1 CRDs + a public Gateway to attach muster's HTTPRoute to
- shared-configs with an `agentic-platform` app template (renders values
  under the `muster:` umbrella prefix)

## Deploying additional charts into `kagent`

This base also provisions a `kagent-flux` ServiceAccount in the `kagent`
namespace (`service-account.yaml`), bound to the built-in `cluster-admin`
`ClusterRole` via a namespace-scoped `RoleBinding` — i.e. full control of all
resources **within `kagent`** only.

The `kagent` namespace itself is **not** created here — it is owned by the
`agentic-platform-connectivity` component (Helm). Flux applies the SA/RoleBinding
once that namespace exists, retrying on its interval until then.

Use it to deploy additional agent-platform charts as `HelmRelease`s living in
the `kagent` namespace. Unlike the umbrella (which lives in the
policy-exempt `flux-giantswarm`), a `HelmRelease` in `kagent` is subject to the
`flux-multi-tenancy` Kyverno policy, so it **must** set `serviceAccountName` and
target its own namespace:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <chart>
  namespace: kagent
spec:
  serviceAccountName: kagent-flux   # required by flux-multi-tenancy Kyverno policy
  targetNamespace: kagent           # must be local (targetNamespaceMustBeLocal rule)
  ...
```

Because the binding is namespace-scoped, such charts can only create namespaced
resources in `kagent`; cluster-scoped resources (CRDs, ClusterRoles) are denied.

## Creating agents (tenant self-service)

Tenants create agents with the generic
[`agent` chart](https://github.com/giantswarm/agent) (one Helm release = one
agent), typically as a `HelmRelease` in `kagent` using the `kagent-flux`
ServiceAccount described above. The admin-owned resources the chart relies on
(see the [creating-agents PRD](https://github.com/giantswarm/bumblebee-plans/blob/main/creating-agents/PRD.md))
are all rendered by the umbrella — **no extra CRs need to be applied via
GitOps**:

- **`ModelConfig` + LLM credentials**: the kagent component renders
  `default-model-config` and creates the `kagent-anthropic` Secret in the
  `kagent` namespace from `kagent.providers.anthropic.apiKey`, which is
  SOPS-encrypted per cluster in giantswarm-configs under
  `installations/<mc>/apps/agentic-platform/`. Rotate the key there; additional
  catalog entries go in the `agents.models` values.
- **Shared muster `RemoteMCPServer`**: the `agentic-platform-connectivity`
  component renders a `RemoteMCPServer` named `muster` in the
  `agentic-platform` namespace with `allowedNamespaces: {from: All}` — the
  server the agent chart's `serverRef` defaults to. Controlled via the
  `agents.muster.shared` values.

## Related

- [agentic-platform chart](https://github.com/giantswarm/agentic-platform)
- [Muster MC Deployment Concept](https://github.com/giantswarm/muster/blob/main/docs/concepts/mc-deployment.md)
