# Backstage

To enable backstage on your management cluster
this base should be used.

> **Warning** All operations carried out as part of this enablement set are
> carried out on your `CUSTOMER_NAME-management-clusters` repository.
>
> Do not raise PRs to enable backstage on your management cluster against this
> repository. It will neither work, nor be accepted.
>
> If you do not know what your `CUSTOMER_NAME-management-clusters` repository is
> please talk to your account engineer.

This base provides a generalised template for deploying backstage core to your
management cluster using versions of backstage that have been tested by
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
  - https://github.com/giantswarm/management-cluster-bases//extras/backstage/?ref=main
  - ../backstage
patches:
  - patch: |
      apiVersion: helm.toolkit.fluxcd.io/v2beta1
      kind: HelmRelease
      metadata:
        name: backstage
        namespace: flux-giantswarm
      spec:
        valuesFrom:
          - kind: ConfigMap
            name: backstage-user-values
            valuesKey: values
          - kind: Secret
            name: backstage-user-secrets
            valuesKey: values
          - kind: Secret
            name: backstage-github-app-credentials-secret
            valuesKey: values
    target:
      kind: HelmRelease
      name: backstage
      namespace: flux-giantswarm
```

Next, we need to create the `backstage` subdirectory referenced in the `kustomization.yaml`
with ConfigMap and Secrets. Secret files should be encrypted.

Commit these changes to git and raise a PR to have this merged into the main
branch. Once your PR is accepted and merged, backstage will deploy to your
management cluster during the next full reconcilliation cycle.
