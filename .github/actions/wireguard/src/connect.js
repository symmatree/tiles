import * as core from "@actions/core";
import * as exec from "@actions/exec";
import * as io from "@actions/io";
import * as fs from "fs";

try {
  const vpnConfig = core.getInput("vpn_config");
  core.info(`Wireguard config: ${vpnConfig}`);
  const confDir = core.getInput("conf_dir");
  core.info(`Wireguard config directory: ${confDir}`);

  core.info(`Installing wireguard`);
  await exec.exec('sudo', ['apt-get', '-y',
    '-qq', '-o', 'Dpkg::Progress-Fancy="0"', '-o', 'APT::Color="0"', '-o', 'Dpkg::Use-Pty="0"',
    'install', 'wireguard-tools']);
  await io.mkdirP(confDir);
  fs.writeFileSync(`${confDir}/wg0.conf`, vpnConfig, { mode: 0o600 });

  core.info(`Connecting`);
  await exec.exec('sudo', ['wg-quick', 'up', `${confDir}/wg0.conf`]);
  core.info(`Connected`);
} catch (error) {
  core.setFailed(error.message);
}
