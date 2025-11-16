import * as core from "@actions/core";
import * as exec from "@actions/exec";

try {
  core.info(`Disconnecting`);
  const confDir = core.getInput("conf_dir");
  // await exec.exec('sudo', ['wg-quick', 'down', `${confDir}/wg0.conf`]);
  await exec.exec('sudo', ['ip', 'link', 'delete', 'dev', 'wg0']);
  core.info(`Disconnected`);
} catch (error) {
  core.setFailed(error.message);
}
