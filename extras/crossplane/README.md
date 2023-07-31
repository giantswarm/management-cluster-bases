# Crossplane

To enable [crossplane](https://docs.crossplane.io/) on your management cluster
this base should be used.

If crossplane is already enabled on your management cluster and you wish to
install providers, please see the additional documentation under
[providers/upbound](./providers/upbound)

> **Warning** All operations carried out as part of this enablement set are
> carried out on your `CUSTOMER_NAME-management-clusters` repository.
>
> Do not raise PRs to enable crossplane on your management cluster against this
> repository. It will neither work, nor be accepted.
>
> If you do not know what your `CUSTOMER_NAME-management-clusters` repository is
> please talk to your account engineer.

This base provides a generalised template for deploying crossplane core to your
management cluster using versions of crossplane that have been tested by
ourselves and are guaranteed to work inside our environment.

Inside your management-clusters repository, you will find a structure such as:

```nohighlight
.
├── bases
│   ├── flux-app
│   │   └── crds
│   │       └── kustomization.yaml
│   └── patches
│       └── kustomization-post-build.yaml
├── management-clusters
│   └── MC_NAME
│       ├── catalogs
│       │   ├── kustomization.yaml
│       │   └── patches
│       │       └── ...
│       ├── configmap-management-cluster-metadata.yaml
│       ├── extras
│       │   └── kustomization.yaml
...
```

The `Kustomization` we're interested in is `management-clusters/MC_NAME/extras`

Open the `kustomization.yaml` file and add the following information. Take care
to only append this information to existing sections to ensure existing resources
are not accidentally removed from your cluster.

Replace all instances of `MC_NAME` with the name of your management cluster.

```yaml
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/crossplane/?ref=main
patches:
  - path: patch-crossplane-helmrelease.yaml
    target:
      kind: HelmRelease
      name: crossplane
      namespace: flux-giantswarm
  - patch: |
      apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
      kind: Kustomization
      metadata:
        name: crossplane-providers
        namespace: flux-giantswarm
      spec:
        path: "./management-clusters/MC_NAME/crossplane-providers"
    target:
      kind: Kustomization
      name: crossplane-providers
      namespace: flux-giantswarm
```

Next, we need to create the `crossplane-providers` subdirectory with an empty
kustomization. This directory will be populated with providers as and when we
know which provider-family members are required for the infrastructure we're
building.

```bash
mkdir management-clusters/MC_NAME/crossplane-providers
echo "resources: []" > management-clusters/MC_NAME/crossplane-providers/kustmization.yaml
```

Commit these changes to git and raise a PR to have this merged into the main
branch. Once your PR is accepted and merged, crossplane will deploy to your
management cluster during the next full reconcilliation cycle.

## Enabling alpha and beta flags to crossplane

Crossplane supports additional feature flags for enabling alpha and beta
functionality to the crossplane pod.

**Warning** We do not advise running this on any crossplane installation handling
production workloads. This must only ever be used for testing purposes.

Edit the `management-clusters/MC_NAME/extras/kustomization.yaml` and append the
following patch.

```yaml
  - op: add
    path: /spec/values/args
    value:
      - --beta-feature-flag
      - --alpha-feature-flag
    target:
      kind: HelmRelease
      name: crossplane
      namespace: flux-giantswarm
```
