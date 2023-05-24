## About this base

This base delivers the GitOps Server app and preliminary configuration for it, i.e. it:

* enables OIDC login and disables local-user login.
* enables ingress creation.
* enables debug-level logging.

## Usage

In order to use this base it must be referenced in the `management-clusters/MC_NAME/extras/kustomization.yaml` file, and then further configured with installation-specific parts, see next paragraphs.

### SOPS encryption

Check the [.sops.keys](../../.sops.yaml) file to determine if the installation you are going to configure this base for is already SOPS-enabled. If it is, then go straight to the [enabling decryption for `flux-extras` section](#enabling-decryption-for-flux-extras). If not, then follow all the next paragraphs.

#### Creating the AGE key pair

The AGE key pair can easily be generated using the `age` binary, for example:

```sh
$ age-keygen
# public key: PUBLIC_KEY
AGE-SECRET-KEY-PRIVATE_KEY
```

Take the private key, with the `AGE-SECRET-KEY-` part, and put it into the LastPass as a `MC_NAME.agekey` security note under the `Shared-Dev Common/Installation` folder.

Then, create the Kubernetes Secret with it in the cluster:

```sh
$ cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  labels:
    konfigure.giantswarm.io/data: sops-keys
  name: sops-keys
  namespace: flux-giantswarm
stringData:
  PUBLIC_KEY.agekey: PRIVATE_KEY
EOF
```

**IMPORTANT**, how the Secret is managed is out of scope of this short document. But one of the options is to store it in the repository itself, and configure the main, `flux`, Kustomization to deliver it.

#### Enabling encryption

Take the public key and use it to create an entry for the installation in the [.sops.keys](../../.sops.yaml) file:

```yaml
creation_rules:
  - age: PUBLIC_KEY
    path_regex: management-clusters/MC_NAME/.*(secret|credential).*
    encrypted_regex: ^(data|stringData)$
```

This instructs SOPS of which key to use, and for which files, when encrypting stuff in the repository.

#### Enabling decryption for `flux-extras`

Create a patch for the `flux-extras` Kustomization in the installation directory, for example:

```sh
$ cat <<EOF > management-clusters/MC_NAME/patch-kustomization-flux-extras.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: flux-extras
  namespace: flux-giantswarm
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-keys
EOF
```

After doing that, update the `management-clusters/MC_NAME/kustomization.yaml` with reference to the file just created:

```yaml
patches:
 - path: patch-kustomization-flux-extras.yaml
   target:
     kind: Kustomization
     name: flux-extras
     namespace: flux-giantswarm
```

With this in place, the `flux-extras` Kustomization should get updated with decryption configuration. Now you can proceed to adding sensitive information to the repository and encrypt it with SOPS.

### Configuring OIDC client secret

First, generate the installation-unique client secret, for example:

```sh
$ openssl rand -base64 32
CLIENT_SECRET
```

Then, use it to create the `gitops-server-secret.yaml` file, with `values.yaml` inside, under the `management-clusters/MC_NAME/extras` directory:

```sh
$ cat <<EOF > management-clusters/MC_NAME/extras/gitops-server-secret.yaml
apiVersion: v1
stringData:
    values.yaml: |
      oidcSecret:
        clientSecret: "CLIENT_SECRET"
kind: Secret
metadata:
    name: gitops-server-values
    namespace: flux-giantswarm
EOF
```

Now, update the `management-clusters/MC_NAME/extras/kustomization.yaml` file with reference to the newly created secret:

```yaml
resources:
  - ../../../extras/gitops-server/
  - gitops-server-secret.yaml
```

And then, use SOPS to encrypt the file:

```sh
$ sops --encrypt --in-place management-clusters/MC_NAME/extras/gitops-server-secret.yaml
```

Now, the `gitops-server` HelmRelease CR may get patched to use the secret, and also with other installation-specific configuration.

**IMPORTANT**: remember about configuring Dex app in the `config` repository with the client secret just created, [like so](https://github.com/giantswarm/config/pull/1663/files).

### Update the `gitops-server` HelmRelease CR

Create the patch for HelmRelease, inside the `management-clusters/MC_NAME/extras`, with:

* reference to the `values.yaml` created in the previous paragraph.
* installation-specific ingress configuration.
* installation-specific registry configuration, if needed.

See an example below.

```sh
$ cat <<EOF > management-clusters/MC_NAME/extras/patch-helmrelease-gitops-server.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: gitops-server
  namespace: flux-giantswarm
spec:
  values:
    image:
      registry: PROVIDER_OR_INSTALLATION_SPECIFIC_REGISTRY
    oidcSecret:
      issuerURL: https://dex.g8s.INSTALLATION_SPECIFIC_DOMAIN
      redirectURL: https://gitops.g8s.INSTALLATION_SPECIFIC_DOMAIN/oauth2/callback
    ingress:
      hosts:
        - host: gitops.g8s.INSTALLATION_SPECIFIC_DOMAIN
          paths:
            - path: /
              pathType: ImplementationSpecific
      tls:
        - hosts:
            - gitops.g8s.INSTALLATION_SPECIFIC_DOMAIN
          secretName: gitops-tls
  valuesFrom:
    - kind: Secret
      name: gitops-server-values
EOF
```

Next, update the `management-clusters/MC_NAME/extras/kustomization.yaml` to apply the patch:

```yaml
patches:
  - path: patch-helmrelease-gitops-server.yaml
    target:
      kind: HelmRelease
      name: gitops-server
      namespace: flux-giantswarm
```
### Create the `gitops-server` NetworkPolicy

```sh
$ cat <<EOF > management-clusters/MC_NAME/extras/network-policy-acme.yaml
# Temporary NetworkPolicy for allowing the ACME challenge-related
# traffic.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dashboard-acme-ingress
  namespace: flux-system
spec:
  ingress:
  - ports:
    - port: 8089
      protocol: TCP
  podSelector:
    matchLabels:
      acme.cert-manager.io/http01-solver: "true"
  policyTypes:
  - Ingress
EOF
```
Now, update the `management-clusters/MC_NAME/extras/kustomization.yaml` file with reference to the newly created policy:

```yaml
resources:
  - ../../../extras/gitops-server/
  - gitops-server-secret.yaml
  - network-policy-acme.yaml
```
