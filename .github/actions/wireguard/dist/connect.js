import { r as requireIo, c as coreExports, e as execExports } from './exec-CWafDCaz.js';
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
  const vpnConfig = coreExports.getInput("vpn_config");
  coreExports.info(`Wireguard config: ${vpnConfig}`);
  const confDir = coreExports.getInput("conf_dir");
  coreExports.info(`Wireguard config directory: ${confDir}`);

  coreExports.info(`Installing wireguard`);
  await execExports.exec('sudo', ['apt-get', '-y',
    '-qq', '-o', 'Dpkg::Progress-Fancy="0"', '-o', 'APT::Color="0"', '-o', 'Dpkg::Use-Pty="0"',
    'install', 'wireguard-tools']);
  await ioExports.mkdirP(confDir);
  require$$1.writeFileSync(`${confDir}/wg0.conf`, vpnConfig, { mode: 0o600 });

  coreExports.info(`Connecting`);
  await execExports.exec('sudo', ['wg-quick', 'up', `${confDir}/wg0.conf`]);
  coreExports.info(`Connected`);
} catch (error) {
  coreExports.setFailed(error.message);
}
//# sourceMappingURL=connect.js.map
