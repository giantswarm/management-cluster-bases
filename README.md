# Management Cluster Bases

Note: We may refer to this repository using the acronym **MCB**.

## Purpose of this repository

At Giant Swarm, we apply GitOps to provision and configure management clusters. This **public** repository holds common configuration used by all management clusters.

In addition, each Giant Swarm customer has their dedicated repository for private and specific configuration.

To learn more about how GitOps works with Giant Swarm, check our [GitOps documentation](https://docs.giantswarm.io/advanced/gitops/gitops-at-giantswarm/).

## Content structure

- `bases`: definitions for Flux deployments
  - `catalogs`: app catalogs
  - `flux-app`: definitions for two separate instances of [flux-app](https://github.com/giantswarm/flux-app)
    - `customer`: the flux-app instance deployed to `flux-system`, plus all the additional RBAC, Kyverno policies etc.
    - `giantswarm`: the `flux-app` instance deployed to `flux-giantswarm` with necessary patches, RBAC, K8s resources.
  - `flux-giantswarm-resources`: resources created in the `flux-giantswarm` namespace during the management cluster bootstrapping process
  - `provider`: definitions for all the infrastructure providers we serve.
- `extras`: collection of patches, additional resources, and mix-ins used by several management clusters.

## Tools

In order to upgrade Flux App and `konfigure` bump the versions in `Makefile.custom.mk` and run the following command:

```shell
make ensure-versions
```

To build the catalogs with their default values:

```shell
make build-catalogs-with-defaults
```
