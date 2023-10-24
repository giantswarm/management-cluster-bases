# Flux v2 migration guide

Management clusters are migrated one by one via pointing to Flux v2 version of their provider bases.

## CMC changes

In the CMC repositories do the following steps.

### CRDs

Update to Flux v2 CRDs in `management-clusters/<MC_NAME>/crds/kustomization.yaml` by replacing the reference of
`https://github.com/giantswarm/management-cluster-bases//bases/crds/common?ref=main` to `//bases/crds/common-flux-v2?ref=main`.

```yaml
# management-clusters/<MC_NAME>/crds/kustomization.yaml
resources:
  - https://github.com/giantswarm/management-cluster-bases//bases/crds/common-flux-v2?ref=main
```

### The `flux` kustomization

Update to the Flux v2 provider base in `management-clusters/<MC_NAME>>/kustomization.yaml` by replacing the reference of
`https://github.com/giantswarm/management-cluster-bases//bases/provider/<PROVIDER>/?ref=main` to `//bases/provider/<PROVIDER>/flux-v2?ref=main`.

### Compatibility with `kustomize` version `v5+`

Do this step for the existing `kustomization.yaml` files and check for MC specific resources and update them
for Flux v2, but mostly because of `kustomize@v5+` compatibility.

For example for Flux git repositories:

- get rid of `.spec.gitImplementation` field

For `kustomization.yaml` files these will cover most of our cases:

- collapse `patchesStrategicMerge` and `patchesJson6902` to `patches`
- collapse `bases` into `resources`

For more details see: https://github.com/fluxcd/flux2/releases/tag/v2.0.0 and https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv5.0.0

## Deployment

### Check generated diff merging

Check the generated diff on the pull request. It should contain including but not limited to:

- the new `ResourceQuota` resource added by upstream Flux
- updated image versions for Flux controllers
- updated labels and annotations for Flux resources
- some security context related changes

### Merge to main branch and update `kustomize-controller` deployment

After merging to `main` branch, the `flux-giantswarm/kustomize-controller` deployment will need to be manually updated
on the MC to use the `v1.0.1` image of `giantswarm/kustomize-controller:v1.0.1` for 2 containers:

- the `ensure-sopsenv` init container
- the `manager` container

This is needed because the Flux git repositories will get updated to v1 once the Flux v2 CRDs are rolled out and the
`.status.artifact.checksum` field gets removed from the CRs making the Flux v1 `kustomize-controller` fail on fetching
the source artifacts. For more details: https://github.com/fluxcd/flux2/releases/tag/v2.0.0.

Upon manually bumping the image Flux will unblock itself and should start reconciling itself
and other resources fine.
