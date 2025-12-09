# mcp-kubernetes MCB Extra

This directory contains the MCB extra for deploying mcp-kubernetes as a HelmRelease
with configuration rendered by the Konfiguration operator.

## How it works

1. **Konfiguration CR** (`konfiguration.yaml`) - Tells the Konfiguration operator to render
   the templates from `shared-configs/default/apps/mcp-kubernetes/` with cluster-specific variables.

2. **HelmRelease** (`helm-release.yaml`) - References the Konfiguration-rendered ConfigMap:
   - `mcp-kubernetes-konfiguration` ConfigMap - Contains rendered values from shared-configs template

3. **Configuration Sources**:
   - Template: `shared-configs/default/apps/mcp-kubernetes/configmap-values.yaml.template`
   - Variables: Cluster-specific values from `shared-configs/default/config.yaml`

4. **Secrets**: OAuth credentials are stored directly as a Kubernetes Secret in each cluster's
   extras directory (`oauth-credentials.enc.yaml`), encrypted with SOPS.

## Prerequisites

For the Konfiguration to work, the `flux-extras` Kustomization must pass the `cluster_name` variable.

Add this target to the `replacements` section in `giantswarm-management-clusters/management-clusters/<cluster>/kustomization.yaml`:

```yaml
replacements:
  - source:
      kind: ConfigMap
      name: management-cluster-metadata
      namespace: flux-giantswarm
      fieldPath: data.NAME
    targets:
      # ... existing targets ...
      - select:
          kind: Kustomization
          name: flux-extras
          namespace: flux-giantswarm
        fieldPaths:
          - spec.postBuild.substitute.cluster_name
        options:
          create: true
```

## Deploying to a cluster

1. Add the extra to the cluster's `extras/kustomization.yaml`:

```yaml
resources:
  - ./mcp-kubernetes/
```

2. Create `extras/mcp-kubernetes/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-kubernetes?ref=main
  - oauth-credentials.enc.yaml
```

3. Create `extras/mcp-kubernetes/oauth-credentials.enc.yaml` with SOPS-encrypted OAuth secrets:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-kubernetes-oauth-credentials
  namespace: mcp-kubernetes
type: Opaque
stringData:
  dex-client-secret: <encrypted-secret>
  registration-token: ""
  oauth-encryption-key: <encrypted-key>
```

Then encrypt with SOPS using the cluster's age key.

4. The configuration will be automatically rendered by Konfiguration using shared-configs
   and cluster-specific values from CMC repositories.
