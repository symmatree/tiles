{
  local this = self,
  _config+:: {
    cluster_name: error 'cluster_name is required',
    vault_name: error 'vault_name is required',
    cluster_issuer: error 'cluster_issuer is required',

    ingressClassName: 'cilium',
    ingressAnnotations: {
      'cert-manager.io/cluster-issuer': this._config.cluster_issuer,
    },
    domain: this._config.cluster_name + '.symmatree.com',
    unifi: {
      name: 'unifi',
      image: "ghcr.io/enuno/unifi-mcp-server:v0.2.1",
      podLabels: {
        app: this._config.unifi.name,
      },
      port: 443,
      verifySsl: true,
      unifiHost: 'morpheus.local.symmatree.com',
      secretName: 'tiles-unifi-mcp-api-key',
      secretPath: 'op://' + this._config.vault_name + '/items/tiles-unifi-mcp-api-key',
      mcpPort: 8000,
      mcpToolboxPort: 8080,
      host: 'unifi-mcp.' + this._config.domain,
      toolboxHost: 'unifi-mcp-toolbox.' + this._config.domain,

    }
  },
}
