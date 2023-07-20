# Enabling providers and provider family members for Azure

Please see [service account labels and annotations](https://azure.github.io/azure-workload-identity/docs/topics/service-account-labels-and-annotations.html)
for a full set of annotations that may be used on Azure

## Example `Kustomization`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/crossplane/providers/upbound/azure?ref=main
patches:
  - patch: |
      - op: replace
        path: /metadata/name
        value: provider-azure-${PROVIDER}
      - op: replace
        path: /spec/serviceAccountName
        value: upbound-provider-azure-${PROVIDER}
      - op: add
        path: /spec/metadata/annotations/azure.workload.identity~1use
        value: true
    target:
      kind: ControllerConfig
  - patch: |
      - op: replace
        path: /metadata/name
        value: provider-azure-${PROVIDER}
      - op: replace
        path: /spec/controllerConfigRef/name
        value: provider-azure-${PROVIDER}
      - op: replace
        path: /spec/package
        value: xpkg.upbound.io/upbound/provider-azure-${PROVIDER}:v0.37.0
    target:
      kind: Provider
  - patch: |
      - op: replace
        path: /metadata/name
        value: upbound-provider-azure-${PROVIDER}
      - op: add
        path: /metadata/annotations/azure.workload.identity~1client-id
        value: REPLACE_ME_WITH_CLIENT_ID
      - op: add
        path: /metadata/annotations/azure.workload.identity~1tenant-id
        value: REPLACE_ME_WITH_TENANT_ID
    target:
      kind: ServiceAccount
  - patch: |
     - op: replace
       path: /metadata/name
       value: crossplane-use-psp-upbound-provider-azure-${PROVIDER}
     - op: replace
       path: /subjects/0/name
       value: upbound-provider-azure-${PROVIDER}
    target:
      kind: ClusterRoleBinding
```
