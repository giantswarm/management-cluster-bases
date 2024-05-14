# Enable zot policies

This policy sets an `extraConfigs` `ConfigMap` for `App` CRs that are created using `cluster-aws` app in a namespace starting with `org-*`. The injected ConfigMap configures `containerd` to use the `zot` cache that is available on the installation's MC.

## How to install

This Kyverno policy requries flux `postBuild` instruction in order to setup a correct URL for cache. Example:

```yaml
kind: Kustomization
spec:
  force: false
  interval: 1m0s
  path: ./
  postBuild:
    substitute:
      zot_url: ${ZOT_URL}
```
