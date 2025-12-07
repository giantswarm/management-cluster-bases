# mcp-kubernetes kustomizations

MCP Kubernetes is a Model Context Protocol server for Kubernetes, allowing AI assistants like Cursor to interact with Kubernetes clusters.

## Installation

mcp-kubernetes is installed as a `HelmRelease` and uses `ConfigMaps/Secrets` as values sources.

### Basic Installation

Reference the MCB extra directly:

```yaml
# management-clusters/<mc>/extras/kustomization.yaml
resources:
  - ./mcp-kubernetes/
```

Create the mcp-kubernetes directory with:

```yaml
# management-clusters/<mc>/extras/mcp-kubernetes/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - oauth-credentials.enc.yaml
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-kubernetes?ref=main

configMapGenerator:
  - name: mcp-kubernetes-user-values
    namespace: mcp-kubernetes
    files:
      - values=user-values.yaml
    options:
      disableNameSuffixHash: true

patches:
  - patch: |-
      - op: add
        path: /spec/valuesFrom/-
        value:
          kind: ConfigMap
          name: mcp-kubernetes-user-values
          valuesKey: values
    target:
      kind: HelmRelease
      name: mcp-kubernetes
  - patch: |-
      - op: add
        path: /spec/valuesFrom/-
        value:
          kind: Secret
          name: mcp-kubernetes-oauth-credentials
          valuesKey: values
    target:
      kind: HelmRelease
      name: mcp-kubernetes
```

## Configuration

### User Values (user-values.yaml)

Create a `user-values.yaml` file with cluster-specific configuration.

The configuration values are rendered by the Konfiguration system from templates in `shared-configs/default/apps/mcp-kubernetes/`.

Example user-values.yaml:

```yaml
ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: mcp-kubernetes.g8s.grizzly.gaws.gigantic.io
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: mcp-kubernetes-tls
      hosts:
        - mcp-kubernetes.g8s.grizzly.gaws.gigantic.io

mcpKubernetes:
  kubernetes:
    inCluster: true
  oauth:
    enabled: true
    provider: "dex"
    baseURL: "https://mcp-kubernetes.g8s.grizzly.gaws.gigantic.io"
    dex:
      issuerURL: "https://dex.g8s.grizzly.gaws.gigantic.io"
      clientID: "DYWmHGubcvG59OTbLBaepYnEeVXHgwaB"
      connectorID: "giantswarm-ad"
    # Cursor compatibility flags - REQUIRED for Cursor integration
    allowPublicRegistration: true
    registrationAccessToken: ""
    allowInsecureAuthWithoutState: true
    maxClientsPerIP: 10
    # Production security features
    encryptionKey: true
    disableStreaming: false
    enableDownstreamOAuth: true
    existingSecret: "mcp-kubernetes-oauth-credentials"
```

### OAuth Credentials Secret

Create `oauth-credentials.enc.yaml` with SOPS-encrypted OAuth credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-kubernetes-oauth-credentials
  namespace: mcp-kubernetes
type: Opaque
stringData:
  values: |
    mcpKubernetes:
      oauth:
        dex:
          clientSecret: <dex-client-secret>
        registrationToken: ""
        oauthEncryptionKey: <openssl rand -base64 32>
```

Encrypt with SOPS using the MC's age key.

### Dex Client Configuration

Add the mcp-kubernetes client to dex-app. In `shared-configs/default/apps/dex-app/configmap-values.yaml.template`:

```yaml
oidc:
  staticClients:
    mcpKubernetes:
      clientID: 'DYWmHGubcvG59OTbLBaepYnEeVXHgwaB'
      redirectURI: {{ .services.mcpkubernetes.protocol }}://{{ .services.mcpkubernetes.subDomain }}.{{ .base }}/oauth/callback
      public: false
      name: MCP Kubernetes
```

And add the client secret in `<customer>-configs/installations/<mc>/apps/dex-app/secret-values.yaml.patch`.

### Private Clusters

For private clusters, use a different cluster issuer:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: private-giantswarm
```

## Verification

After deployment, verify the installation:

```bash
# Check HelmRelease status
kubectl get helmrelease -n flux-giantswarm mcp-kubernetes

# Check pod is running
kubectl get pods -n mcp-kubernetes

# Check ingress
kubectl get ingress -n mcp-kubernetes
```

## Troubleshooting

### HelmRelease Not Ready

Check the HelmRelease status and events:

```bash
kubectl describe helmrelease -n flux-giantswarm mcp-kubernetes
```

### OAuth Issues

1. Verify the dex-app configuration includes the mcp-kubernetes client
2. Check that the client secret in mcp-kubernetes matches the one in dex-app
3. Verify the OAuth callback URL is correctly configured in dex
