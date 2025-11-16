import { c as coreExports, e as execExports } from './exec-nEg6paeE.js';
import 'os';
import 'crypto';
import 'fs';
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

try {
  coreExports.info(`Disconnecting`);
  const confDir = coreExports.getInput("conf_dir");
  // await exec.exec('sudo', ['wg-quick', 'down', `${confDir}/wg0.conf`]);
  await execExports.exec('sudo', ['ip', 'link', 'delete', 'dev', 'wg0']);
  coreExports.info(`Disconnected`);
} catch (error) {
  coreExports.setFailed(error.message);
}
//# sourceMappingURL=disconnect.js.map
