import { r as requireIo, c as coreExports, e as execExports } from './exec-nEg6paeE.js';
import * as require$$1 from 'fs';
import 'os';
import 'crypto';
import 'path';
import 'http';
import 'https';
import 'net';
import 'tls';
import 'events';
import 'assert';
import 'util';
import 'stream';
import 'buffer';
import 'querystring';
import 'stream/web';
import 'node:module';
import 'worker_threads';
import 'perf_hooks';
import 'util/types';
import 'async_hooks';
import 'console';
import 'url';
import 'zlib';
import 'string_decoder';
import 'diagnostics_channel';
import 'child_process';
import 'timers';

var ioExports = requireIo();

try {
  // const vpnConfig = core.getInput("vpn_config");
  // core.info(`Wireguard config: ${vpnConfig}`);
  const confDir = coreExports.getInput("conf_dir");
  coreExports.info(`Wireguard config directory: ${confDir}`);
  const privateKey = coreExports.getInput("private_key");
  const publicKey = coreExports.getInput("public_key");
  coreExports.info(`Wireguard public key: ${publicKey}`);
  const endpoint = coreExports.getInput("endpoint");
  coreExports.info(`Wireguard endpoint: ${endpoint}`);
  const allowedIps = coreExports.getInput("allowed_ips");
  coreExports.info(`Wireguard allowed IPs: ${allowedIps}`);
  const clientIp = coreExports.getInput("client_ip");
  coreExports.info(`Wireguard client IP: ${clientIp}`);
  const gatewayIp = coreExports.getInput("gateway_ip");
  coreExports.info(`Wireguard gateway IP: ${gatewayIp}`);

  coreExports.info(`Installing wireguard`);
  await execExports.exec('sudo', ['apt-get', '-y',
    '-qq', '-o', 'Dpkg::Progress-Fancy="0"', '-o', 'APT::Color="0"', '-o', 'Dpkg::Use-Pty="0"',
    'install', 'wireguard', 'wireguard-tools']);
  await ioExports.mkdirP(confDir);
  require$$1.writeFileSync(`${confDir}/privatekey`, privateKey, { mode: 0o600 });

  coreExports.info(`Connecting`);
  // await exec.exec('sudo', ['wg-quick', 'up', `${confDir}/wg0.conf`]);

  await execExports.exec('sudo', ['ip', 'link', 'add', 'dev', 'wg0', 'type', 'wireguard']);
  await execExports.exec('sudo', ['ip', 'address', 'add', 'dev', 'wg0', clientIp, 'peer', gatewayIp]);
  await execExports.exec('sudo', ['wg', 'set', 'wg0', 'private-key', `${confDir}/privatekey`, 'peer', publicKey, 'allowed-ips', allowedIps, 'endpoint', endpoint]);
  await execExports.exec('sudo', ['ip', 'link', 'set', 'up', 'dev', 'wg0']);
  coreExports.info(`Connected`);
} catch (error) {
  coreExports.setFailed(error.message);
}
//# sourceMappingURL=connect.js.map
