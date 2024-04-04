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
## Auth

Since pushing should not be enabled publicly, we need to use some kind of auth. The easiest approach is to go with the `BasicAuth`

By the default config, it's allowed for the `prom` user to access metrics, and for the `admin` user to push images.

Users are not configured by default, because creds should be entrypted, so to add a user, custom values should have the following properties:

```yaml
mountSecret: false
secretFiles:
  # Example htpasswd with 'admin:admin' & 'user:user' user:pass pairs
  htpasswd: |-
    admin:$2y$05$vmiurPmJvHylk78HHFWuruFFVePlit9rZWGA/FbZfTEmNRneGJtha
    prom:$2y$05$L86zqQDfH5y445dcMlwu6uHv.oXFgT6AiJCwpv3ehr7idc0rI3S2G
```

Also, to let prometheus scrape metrics, you need to add a BasicAuth to service monitor. 

To get a snippet of a code that should be encrypted, you can use the script `./make_passwords.sh`

Admin's password will be store in the same secret, where values are stored, it's not going to be used by zot directly, but in case one needs to login as admin, it will be possible to get the password

After the secret is added to the installation, it's required to add it to the `HelmRelease`

```yaml
- op: add
  path: /spec/valuesFrom/-
  value:
    kind: Secret
    name: zot-secret-values
    valuesKey: values.yaml
```
