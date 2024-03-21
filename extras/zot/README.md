# Zot kustomizations

## Additional values

Zot is installed as a `HelmRelease` and it's using `ConfigMaps/Secrest` as values sources. By default, the main configmap with common values is created.

To override or add additional values, one should add a couple of patches to the kustomization on the cluster level. 

```yaml
# This is the default installation
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/zot?ref=main
```

Now, let's say, we need to add `Ingress`

1. We need to add another entry to the values configmap (or we can create another configmap/secret)

```yaml
# Here I'm adding an additional entry
# ./patches/zot-additional-values.yaml
- op: add
  path: /data/custom-values.yaml
  value: |
    ingress:
      enabled: true
      hosts:
        - host: zot.golem.gaws.gigantic.io
          paths:
            - path: /
      tls:
        - secretName: zot-tls
          hosts:
            - zot.golem.gaws.gigantic.io

```

2. We need to let flux know that these values should be used

```yaml
# ./patches/zot-release.yaml
- op: add
  path: /spec/valuesFrom/-
  value:
    kind: ConfigMap
    name: zot-config
    valuesKey: custom-values.yaml
```

3. Add patches to the kustomization

```yaml
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/zot?ref=main
patches:
  - target:
      version: v1
      kind: ConfigMap
      name: zot-config
    path: ./patches/zot-additional-values.yaml
  - target:
      group: helm.toolkit.fluxcd.io
      version: v2beta1
      kind: HelmRelease
      name: zot
    path: ./patches/zot-release.yaml
```
