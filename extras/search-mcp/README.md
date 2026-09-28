# search-mcp

[search-mcp](https://github.com/giantswarm/search-mcp) serves the public Giant Swarm documentation and handbook as MCP tools.
It runs in-cluster in the `search-mcp` namespace, without a route and without OAuth, so it offers only the public tools.
The management cluster registers it with muster as an `MCPServer` (auth `none`) at
`http://search-mcp.search-mcp.svc.cluster.local/mcp`.

The chart follows the newest release (`semver: ">=0.0.0"`).

An installation can pass chart values through an optional ConfigMap `search-mcp-user-values`
(key `values`) in `flux-giantswarm`, for example the forwarded-token settings with which
search-mcp reaches the intranet as each caller.
