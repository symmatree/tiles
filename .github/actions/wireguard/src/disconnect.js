import * as core from "@actions/core";
import * as exec from "@actions/exec";

try {
  core.info(`Disconnecting`);
  await exec.exec('sudo', ['wg-quick', 'down', `${confDir}/wg0.conf`]);
  core.info(`Disconnected`);
} catch (error) {
  core.setFailed(error.message);
}
