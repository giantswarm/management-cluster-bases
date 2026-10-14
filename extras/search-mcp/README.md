# search-mcp

[search-mcp](https://github.com/giantswarm/search-mcp) serves the public Giant Swarm documentation and handbook as MCP tools.
It runs in-cluster in the `search-mcp` namespace, without a route and without OAuth, so it offers only the public tools.
The management cluster registers it with muster as an `MCPServer` (auth `none`) at
`http://search-mcp.search-mcp.svc.cluster.local/mcp`.

Capped at the newest stable the fleet runs; test installations follow newer
stable releases first. See [mcp-kubernetes](../mcp-kubernetes/README.md#version-strategy).

An installation can pass chart values through an optional ConfigMap `search-mcp-user-values`
(key `values`) in `flux-giantswarm`, for example the forwarded-token settings with which
search-mcp reaches the intranet as each caller.
