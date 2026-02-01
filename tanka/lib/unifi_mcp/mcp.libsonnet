local k_util = import 'github.com/grafana/jsonnet-libs/ksonnet-util/util.libsonnet';
local k = import 'k.libsonnet';
local libop = import 'op.libsonnet';

(import 'config.libsonnet') +
{
    local this = self,
    local kDeployment = k.apps.v1.deployment,
    local kContainer = k.core.v1.container,
    local kContainerPort = k.core.v1.containerPort,
    local kEnvFromSource = k.core.v1.envFromSource,
   local kIngress = k.networking.v1.ingress,
    local kIngressRule = k.networking.v1.ingressRule,
    local kHttpIngressPath = k.networking.v1.httpIngressPath,
    local kIngressTLS = k.networking.v1.ingressTLS,
    local makeIngress(name, host, serviceName, portName) =
      kIngress.new(name)
      + kIngress.metadata.withAnnotations(this._config.ingressAnnotations)
      + kIngress.spec.withIngressClassName(this._config.ingressClassName)
      + kIngress.spec.withRulesMixin([
        kIngressRule.withHost(host)
        + kIngressRule.http.withPathsMixin(
          kHttpIngressPath.withPath('/')
          + kHttpIngressPath.withPathType('Prefix')
          + kHttpIngressPath.backend.service.withName(serviceName)
          + kHttpIngressPath.backend.service.port.withName(portName)
        ),
      ])
      + kIngress.spec.withTlsMixin([
        kIngressTLS.withHosts([host])
        + kIngressTLS.withSecretName(std.format('%s-tls', name)),
      ]),

    unifiSecret: libop.item.new(name=this._config.unifi.secretName,
      itemPath=this._config.unifi.secretPath),

        local healthProbe(probe, port) =
          probe.withInitialDelaySeconds(10)
          + probe.withPeriodSeconds(10)
          + probe.httpGet.withPath('/')
          + probe.httpGet.withPort(port)
          + probe.httpGet.withScheme('HTTP')
          + probe.withSuccessThreshold(1),
        local kLivenessProbe = kContainer.livenessProbe,
        local kReadinessProbe = kContainer.readinessProbe,

    local unifiContainer = kContainer.new('unifi', this._config.unifi.image)
    + kContainer.withEnvMap({
        UNIFI_API_TYPE: 'local',
        UNIFI_LOCAL_HOST: this._config.unifi.unifiHost,
        UNIFI_LOCAL_PORT: std.toString(this._config.unifi.port),
        UNIFI_LOCAL_VERIFY_SSL: std.toString(this._config.unifi.verifySsl),
        FASTMCP_TRANSPORT: 'sse',
        FASTMCP_PORT: std.toString(this._config.unifi.mcpPort),
    }) + kContainer.withEnvFromMixin(
        // We expect UNIFI_API_KEY from this secret
        kEnvFromSource.secretRef.withName(this._config.unifi.secretName)
    ) + kContainer.withCommand(["python", "-m", "src.main"])
    + kContainer.withPorts([
        kContainerPort.newNamed(this._config.unifi.mcpPort, 'mcp'),
        kContainerPort.newNamed(this._config.unifi.mcpToolboxPort, 'mcp-toolbox'),
    ])
        + healthProbe(kLivenessProbe, this._config.unifi.mcpToolboxPort)
        + kLivenessProbe.withFailureThreshold(6)
        + healthProbe(kReadinessProbe, this._config.unifi.mcpToolboxPort)
        + kReadinessProbe.withFailureThreshold(3),
    unifiDeployment: kDeployment.new(this._config.unifi.name, containers=[unifiContainer], podLabels=this._config.unifi.podLabels),
    unifiService: k_util.serviceFor(this.unifiDeployment),
    unifiIngress: makeIngress(this._config.unifi.name, host=this._config.unifi.host, serviceName=this.unifiService.metadata.name, portName='mcp'),
   unifiToolboxIngress: makeIngress(this._config.unifi.name + '-toolbox', host=this._config.unifi.toolboxHost, serviceName=this.unifiService.metadata.name, portName='mcp-toolbox'),
}
