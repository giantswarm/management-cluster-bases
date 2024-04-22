# Enable zot policies

These are two policies that are supposed to enable zot as a pull through cache for workload clusters. 

## How does it work?

Once policies are applied, kyverno will be watching new cluster apps. Since a cluster app doesn't have any unique sequence of symbols in any of possible selectors, policies are configured to be checking app's spec to filter out all the other apps. 

Once a new cluster is created, kyverno is supposed to check the config (that is refenced in `spec.userConfig.configMap`) for a string presence. If the config that us used for bootstrapping a new cluster doesn't have any information related to the `gsoci` registry, kyverno should enable mirroring. 

So once one creates a cluster with no configuration for `gsoci`, kyverno is supposed to do two things

1. Create a new ConfigMap with configuration for gsoci
2. Update an app resource, so this new config is refenreced in `extraConfigs`


## How to install

These manifests requies flux `postBuild` instruction in order to setup a correct URL for cache. 

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
