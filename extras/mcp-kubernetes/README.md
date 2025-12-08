# mcp-kubernetes MCB Extra

This directory contains the MCB extra for deploying mcp-kubernetes as a HelmRelease
with configuration rendered by the Konfiguration operator.

## How it works

1. **Konfiguration CR** (`konfiguration.yaml`) - Tells the Konfiguration operator to render
   the templates from `shared-configs/default/apps/mcp-kubernetes/` with cluster-specific variables.

2. **HelmRelease** (`helm-release.yaml`) - References the Konfiguration-rendered ConfigMap and Secret:
   - `mcp-kubernetes-konfiguration` ConfigMap - Contains rendered values from shared-configs template
   - `mcp-kubernetes-konfiguration` Secret - Contains rendered secrets from giantswarm-configs

3. **Configuration Sources**:
   - Template: `shared-configs/default/apps/mcp-kubernetes/configmap-values.yaml.template`
   - Secrets: `giantswarm-configs/installations/<mc>/apps/mcp-kubernetes/secret-values.yaml.patch`

## Prerequisites

For the Konfiguration to work, the `flux-extras` Kustomization must pass the `cluster_name` variable.
Add this to `giantswarm-management-clusters/management-clusters/<cluster>/kustomization.yaml`:

```yaml
replacements:
  - source:
      kind: ConfigMap
      name: management-cluster-metadata
      namespace: flux-giantswarm
      fieldPath: data.NAME
    targets:
      - select:
          kind: Kustomization
          name: flux-extras
          namespace: flux-giantswarm
        fieldPaths:
          - spec.postBuild.substitute.cluster_name
```

## Deploying to a cluster

1. Add the extra to the cluster's `extras/kustomization.yaml`:

```yaml
resources:
  - ./mcp-kubernetes/
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-kubernetes?ref=main
```

2. Create `extras/mcp-kubernetes/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-kubernetes?ref=main
```

3. The configuration will be automatically rendered by Konfiguration using:
   - Cluster-specific values from `shared-configs` variables
   - Secrets from `giantswarm-configs/installations/<mc>/apps/mcp-kubernetes/`

## Secrets

OAuth secrets should be added to `giantswarm-configs/installations/<mc>/apps/mcp-kubernetes/secret-values.yaml.patch`
and encrypted with SOPS.
