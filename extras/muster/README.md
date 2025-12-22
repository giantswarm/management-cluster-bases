# Muster Extras

This directory contains the Flux resources required to deploy muster on a Giant Swarm management cluster.

## Overview

Muster is an MCP (Model Context Protocol) aggregator that:
- Connects to remote MCP servers across all GS management clusters
- Provides OAuth-based authentication to remote servers
- Aggregates tools, resources, and prompts from multiple sources

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Central MC (e.g., gazelle)                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                         muster                              │    │
│  │               (Protected by OAuth Resource Server)         │    │
│  │                                                            │    │
│  │  MCPServer resources → mcp-kubernetes on each MC           │    │
│  └────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

- **muster**: Main MCP aggregator deployment
- **muster-valkey**: Valkey (Redis-compatible) for OAuth session storage

## Configuration

Configuration is managed via:
1. **shared-configs**: `default/apps/muster/configmap-values.yaml.template`
2. **giantswarm-configs**: Per-installation secrets in `<mc>/apps/muster/`

## Secrets Required

Before deployment, ensure these secrets exist in the `muster` namespace:

1. **muster-oauth-credentials**: OAuth encryption key and registration token
   ```bash
   kubectl create secret generic muster-oauth-credentials \
     --namespace muster \
     --from-literal=dex-client-secret=<dex-client-secret> \
     --from-literal=registration-token=$(openssl rand -hex 32) \
     --from-literal=oauth-encryption-key=$(openssl rand -base64 32)
   ```

2. **muster-valkey-auth**: Valkey authentication
   ```bash
   kubectl create secret generic muster-valkey-auth \
     --namespace muster \
     --from-literal=default=$(openssl rand -base64 32)
   ```

## Usage

To deploy muster on a management cluster, reference this extras directory from `giantswarm-management-clusters`:

```yaml
# management-clusters/<mc>/extras/muster/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - git::https://github.com/giantswarm/management-cluster-bases//extras/muster?ref=main
```

## Dependencies

- dex-app >= 2.1.5 (for musterAgent static client support)
- shared-configs with muster app templates

## Related

- [Muster MC Deployment Concept](https://github.com/giantswarm/muster/blob/main/docs/concepts/mc-deployment.md)
- [Muster Auth ADR](https://github.com/giantswarm/muster/blob/main/docs/explanation/decisions/005-muster-auth.md)

