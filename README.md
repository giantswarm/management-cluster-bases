# Management Cluster Bases

Note: We may refer to this repository using the acronym **MCB**.

## Purpose of this repository

At Giant Swarm, we apply GitOps to provision and configure management clusters. This **public** repository holds common configuration used by all management clusters.

In addition, each Giant Swarm customer has their dedicated repository for private and specific configuration.

To learn more about how GitOps works with Giant Swarm, check our [GitOps documentation](https://docs.giantswarm.io/advanced/gitops/gitops-at-giantswarm/).

## Content structure

- `bases`: definitions for Flux deployments
  - `catalogs`: app catalogs
  - `flux-app-v2`: definitions for two separate instances of [flux-app](https://github.com/giantswarm/flux-app).
    - `customer`: the Flux app instance deployed to `flux-system`, plus all the additional RBAC, Kyverno policies etc.
    - `giantswarm`: the Flux app instance deployed to `flux-giantswarm`, split into layers (`common`, `versions/*`, and a `giantswarm` pointer) so its version can be pinned globally and rolled out per management cluster. See [bases/flux-app-v2/README.md](bases/flux-app-v2/README.md).
  - `flux-giantswarm-resources`: resources created in the `flux-giantswarm` namespace during the management cluster bootstrapping process
  - `provider`: definitions for all the infrastructure providers we serve.
- `extras`: collection of patches, additional resources, and mix-ins used by several management clusters.

## Shared workflows

The workflows in `.github/workflows` that declare `on: workflow_call` (`generate_diffs.yaml`, `delete_diffs.yaml` and `lint.yaml`) are reusable: a management-clusters repository calls them with `uses: giantswarm/management-cluster-bases/.github/workflows/<name>.yaml@main`.

A re-run of a workflow run keeps the reusable workflow at the version the original event resolved, so after a fix to a workflow here, give the consumer pull request a new event (push a commit, or close and reopen it); a re-run cannot pick the fix up.

The composite action `.github/actions/organization-kustomizations` refuses an Agent Platform organization's kustomization file under `management-clusters/*/extras/agent-platform-organizations` that loads anything outside its own directory: a field other than `apiVersion`, `kind`, `metadata` and `resources`, or a `resources` entry with `..`, an absolute path, a git or HTTP URL, or a symbolic link. Every management-clusters repository runs it on each pull request through the workflow that devctl generates for the `fleet` flavour (`zz_generated.validate_organization_kustomizations.yaml`). Run it locally from a management-clusters repository with `python3 <this repository>/.github/actions/organization-kustomizations/check-organization-kustomizations.py`.

## Tools

In order to upgrade Flux App and `konfigure` bump the versions in `Makefile.custom.mk` and run the following command:

```shell
make ensure-versions
```

To build the catalogs with their default values:

```shell
make build-catalogs-with-defaults
```
