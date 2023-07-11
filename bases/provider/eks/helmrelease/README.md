# HelmRelease

To deploy your app to a remote cluster, create a new subfolder for your app
and inside that, define two yaml files

- `helmrelease.yaml` Defines the HelmRelease CR (see [example `helmrelease.yaml`](./example-helmrelease.app/helmrelease.yaml))
- `repository.yaml` OPTIONAL - define the repository your helm chart will be
  drawn from (see [example `repository.yaml`](./example-helmrelease-app/repository.yaml))

## `repository.yaml`

The repository.yaml file contains information on where your chart is to be pulled
from. This is similar to the app-platform `catalog` CR  and under normal
circumstances only needs to be defined once for each helm index location.

The `HelmRepository` is a very simple CR type, requiring only the normal metadata
as well as a URL and reconciliation  interval.

> **Note**
>
> In the `giantswarm` catalog type we are allowed to define multiple URLs which
> will be tested in a round-robin fashion.
>
> This allows fallback if a catalog entry becomes unavailable in one location.
>
> `HelmRepository` CR types do not allow this behaviour. Therefore if your
> source becomes unavailable, the release will not progress until such a time
> as the index URL can be reached.
>
> This is likely to introduce additional latency into your chart deployments
> that is outside of our capability to control directly.

If your repository is an OCI style repository, you must set at the very least
the `spec.type` field to `oci` and optionally an additional `Secret` containing
login credentials.

For additional information on `HelmRepository` CRs please see the
[source-controller documentation on this topic](https://github.com/fluxcd/source-controller/blob/main/docs/spec/v1beta2/helmrepositories.md)

## `helmrelease.yaml`

In its simplest form, a `HelmRelease` requires:

```yaml
spec:
  releaseName:      # This is the target name for your deployment
  targetNamespace:  # Which namespace to install your release in to
  kubeConfig:
    secretRef:
      name:         # The name of a secret containing the kubeconfig - MUST be in same namespace as HelmRelease
      key:          # OPTIONAL - a key inside the secret containing the kubeconfig
  chart:
    spec:
      chart:        # The name of the chart being installed
      sourceRef:    # Details of the index containing the chart
        kind: HelmRepository
        name:       # The name of the helm repository index
  interval: 50m     # How often to run the reconcilliation
  install:          # How to  handle install failures
    remediation:
      retries: 3
  values: {}        # Installation specific values
  valuesFrom: []    # An optional list of configmaps and secrets containing values to merge in
```

To compare this to an equivalent App CR

```yaml
spec:
  name:        # The name of the app being deployed
  namespace:   # The target namespace for the deployment
  kubeConfig:
    inCluster: false
    secret:
      name:         # The name of the secret containing the kubeconfig - Must contain a single key containing the kubeconfig
      namespace:    # The namespace the secret is located in
  catalog:          # The name of the catalog containing the chart to deploy
  catalogNamespace: # The namespace the catalog is stored in
  userConfig:
    configMap:      # The name of a configmap to load app values from
    secret:         # The name of a secret to load secret app values from
  extraConfigs: []  # An optional list of configmaps and secrets containing values to merge in in the priority order given
```

Both types contain many other spec options, but these provide an absolute base
that would allow the app to be installed and configured successfully and operate
in almost identical fashions to each other.
