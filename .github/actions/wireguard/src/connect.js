import * as core from "@actions/core";
import * as exec from "@actions/exec";
import * as io from "@actions/io";
import * as fs from "fs";

try {
  // const vpnConfig = core.getInput("vpn_config");
  // core.info(`Wireguard config: ${vpnConfig}`);
  const confDir = core.getInput("conf_dir");
  core.info(`Wireguard config directory: ${confDir}`);
  const privateKey = core.getInput("private_key");
  const publicKey = core.getInput("public_key");
  core.info(`Wireguard public key: ${publicKey}`);
  const endpoint = core.getInput("endpoint");
  core.info(`Wireguard endpoint: ${endpoint}`);
  const allowedIps = core.getInput("allowed_ips");
  core.info(`Wireguard allowed IPs: ${allowedIps}`);
  const clientIp = core.getInput("client_ip");
  core.info(`Wireguard client IP: ${clientIp}`);
  const gatewayIp = core.getInput("gateway_ip");
  core.info(`Wireguard gateway IP: ${gatewayIp}`);

  core.info(`Installing wireguard`);
  await exec.exec('sudo', ['apt-get', '-y',
    '-qq', '-o', 'Dpkg::Progress-Fancy="0"', '-o', 'APT::Color="0"', '-o', 'Dpkg::Use-Pty="0"',
    'install', 'wireguard', 'wireguard-tools']);
  await io.mkdirP(confDir);
  fs.writeFileSync(`${confDir}/privatekey`, privateKey, { mode: 0o600 });

  core.info(`Connecting`);
  // await exec.exec('sudo', ['wg-quick', 'up', `${confDir}/wg0.conf`]);

  await exec.exec('sudo', ['ip', 'link', 'add', 'dev', 'wg0', 'type', 'wireguard']);
  await exec.exec('sudo', ['ip', 'address', 'add', 'dev', 'wg0', clientIp, 'peer', gatewayIp]);
  await exec.exec('sudo', ['wg', 'set', 'wg0', 'private-key', `${confDir}/privatekey`, 'peer', publicKey, 'allowed-ips', allowedIps, 'endpoint', endpoint]);
  await exec.exec('sudo', ['ip', 'link', 'set', 'up', 'dev', 'wg0']);
  core.info(`Connected`);
} catch (error) {
  core.setFailed(error.message);
}
