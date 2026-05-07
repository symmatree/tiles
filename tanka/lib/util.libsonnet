local k = import 'k.libsonnet';
local kServicePort = k.core.v1.servicePort;
local kContainerPort = k.core.v1.containerPort;

{
  // Helper for making sure "overrides" didn't invent a new field that we don't know about
  // and will ignore. Conventional usage asserts just to make the intent clear:
  //
  // local config = defaults + overrides + { args... };
  // assert libutil.checkFields(defaults, config);
  checkFields(defaults, config)::
    local c = std.set(std.objectFields(config));
    local d = std.set(std.objectFields(defaults));
    assert c == d : ('unique fields in _config ' + std.manifestJson(std.setDiff(c, d))
                     + ' and/or defaults ' + std.manifestJson(std.setDiff(d, c)));
    // Return the equality value so the
    c == d,

  // Returns array as-is, or collected field values of an object.
  local valuesForEntity(ent) =
    if std.isArray(ent) then ent else std.objectValues(ent),

  // Takes a map of groups of resources, emits each as a YAML stream.
  toYamlStreams(objs):: {
    [manifest + '.yaml']: std.manifestYamlStream(value=valuesForEntity(objs[manifest]), quote_keys=false)
    for manifest in std.objectFields(objs)
    if objs[manifest] != null
  },

  // Make a container port and a service port targeting it
  local makePort(name, containerPort, servicePort=0, nodePort=0) = {
    // Capture the arguments in a hidden field to allow creating with diff node port.
    config:: { name: name, containerPort: containerPort, nodePort: nodePort },

    service: kServicePort.withName(name)
             + kServicePort.withPort(if servicePort != 0 then servicePort else containerPort)
             + kServicePort.withTargetPort(containerPort)
             + (if nodePort != 0 then kServicePort.withNodePort(nodePort) else {}),
    container: kContainerPort.withName(name) + kContainerPort.withContainerPort(containerPort),
    // Both podMonitor and serviceMonitor take this form, I don't have a helper for it though:
    monitor: { port: name },
  },
  makePort:: makePort,
}
