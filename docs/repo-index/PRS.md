# tiles -- Merged PRs Index

Generated 2026-07-05 via gh.

| # | Merged | Title |
|---|--------|-------|
| [584](https://github.com/symmatree/tiles/pull/584) | 2026-07-05 | Mount the datasets NFS share into JupyterHub singleuser |
| [583](https://github.com/symmatree/tiles/pull/583) | 2026-07-05 | Pin singleuser image by sha tag, pull IfNotPresent |
| [582](https://github.com/symmatree/tiles/pull/582) | 2026-07-05 | docs(bare-metal): install-disk gotcha + fire-and-forget apply |
| [579](https://github.com/symmatree/tiles/pull/579) | 2026-07-05 | Declare lancer taint in tf (heavy:PreferNoSchedule) + per-node taint_effect |
| [578](https://github.com/symmatree/tiles/pull/578) | 2026-07-05 | Move JupyterHub singleuser home to static NFS per-user dirs |
| [577](https://github.com/symmatree/tiles/pull/577) | 2026-07-05 | Pin jupyterhub singleuser to lancer (prod) |
| [574](https://github.com/symmatree/tiles/pull/574) | 2026-07-04 | docs(flight-analysis): add README |
| [572](https://github.com/symmatree/tiles/pull/572) | 2026-07-04 | Pin lancer install disk + wipe so Talos actually installs |
| [571](https://github.com/symmatree/tiles/pull/571) | 2026-07-04 | fix(flight-analysis): strip .pdf suffix before passing to nbconvert --output |
| [570](https://github.com/symmatree/tiles/pull/570) | 2026-07-04 | Wire the mounted SSH key into sshd's AuthorizedKeysFile |
| [569](https://github.com/symmatree/tiles/pull/569) | 2026-07-04 | Enable Mimir mixin: dashboards + recording rules + alerts |
| [567](https://github.com/symmatree/tiles/pull/567) | 2026-07-04 | Fix: restore alertmanager block clobbered in #557 |
| [565](https://github.com/symmatree/tiles/pull/565) | 2026-07-04 | Skip terraform refresh on PR-preview plans (1Password quota, #561) |
| [563](https://github.com/symmatree/tiles/pull/563) | 2026-07-04 | Meter 1Password SA quota per nodes-plan-apply run (#561) |
| [562](https://github.com/symmatree/tiles/pull/562) | 2026-07-05 | Remove dependabot version updates |
| [560](https://github.com/symmatree/tiles/pull/560) | 2026-07-04 | Widen prod kubelet OOM-eviction margin (memory.available 100Mi->512Mi) |
| [559](https://github.com/symmatree/tiles/pull/559) | 2026-07-03 | Add lancer (Strix Halo) as AMD bare-metal worker in prod |
| [558](https://github.com/symmatree/tiles/pull/558) | 2026-07-03 | feat(datascience-notebook-ssh): add playwright, LaTeX, and folium for PDF export |
| [557](https://github.com/symmatree/tiles/pull/557) | 2026-07-03 | Mimir self-monitoring + cardinality API (#556) |
| [555](https://github.com/symmatree/tiles/pull/555) | 2026-07-03 | docs: document metal-rebuild reboot behavior + fix rebuild runbook link |
| [554](https://github.com/symmatree/tiles/pull/554) | 2026-07-03 | flight-analysis: lower memory request 2Gi -> 1Gi |
| [553](https://github.com/symmatree/tiles/pull/553) | 2026-07-03 | Don't let the sshd hook leak set -u into start.sh |
| [551](https://github.com/symmatree/tiles/pull/551) | 2026-07-03 | Fix #547: bare-metal workers reapply + reboot on cluster rebuild |
| [550](https://github.com/symmatree/tiles/pull/550) | 2026-07-03 | Fix #549: drop `terraform init -upgrade` to stop poisoning the TF provider cache |
| [548](https://github.com/symmatree/tiles/pull/548) | 2026-07-03 | flight-analysis: nightly CronJob for .bin log rendering |
| [546](https://github.com/symmatree/tiles/pull/546) | 2026-07-02 | Create /run/sshd before starting sshd in singleuser container |
| [541](https://github.com/symmatree/tiles/pull/541) | 2026-07-03 | Bump hashicorp/google from 7.38.0 to 7.39.0 in /tf/bootstrap |
| [539](https://github.com/symmatree/tiles/pull/539) | 2026-06-30 | Remove never-working Argo CD admin password sync from bootstrap |
| [538](https://github.com/symmatree/tiles/pull/538) | 2026-07-01 | Actually start sshd in the singleuser container |
| [536](https://github.com/symmatree/tiles/pull/536) | 2026-06-28 | Raise VM disk default 32GB -> 100GB |
| [535](https://github.com/symmatree/tiles/pull/535) | 2026-06-28 | Raise jupyterhub singleuser start_timeout to 1800s for cold image pulls |
| [534](https://github.com/symmatree/tiles/pull/534) | 2026-06-28 | Allow privileged pods in jupyterhub namespace |
| [533](https://github.com/symmatree/tiles/pull/533) | 2026-06-28 | Fix ansible_user undefined with local connection |
| [532](https://github.com/symmatree/tiles/pull/532) | 2026-06-28 | Switch repos from squash merge to rebase merge |
| [531](https://github.com/symmatree/tiles/pull/531) | 2026-06-28 | Remove systemd docker task: can't start services during container build |
| [530](https://github.com/symmatree/tiles/pull/530) | 2026-06-27 | Fix lsb_release not found: read Ubuntu codename from /etc/os-release |
| [529](https://github.com/symmatree/tiles/pull/529) | 2026-06-27 | Fix hub secret formats: hex for cookie_secret, Fernet for CryptKeeper.keys |
| [528](https://github.com/symmatree/tiles/pull/528) | 2026-06-27 | bootstrap tf updates |
| [527](https://github.com/symmatree/tiles/pull/527) | 2026-06-27 | Port JupyterHub SSH dev environment from tales to tiles |
| [523](https://github.com/symmatree/tiles/pull/523) | 2026-06-28 | Bump actions/cache from 5 to 6 |
| [519](https://github.com/symmatree/tiles/pull/519) | 2026-06-27 | Bump actions/checkout from 6 to 7 |
| [516](https://github.com/symmatree/tiles/pull/516) | 2026-06-18 | Tune NTRIP seed config for ELRS rover link |
| [513](https://github.com/symmatree/tiles/pull/513) | 2026-06-14 | Lower Argo CD manifest cache TTL to 30m |
| [512](https://github.com/symmatree/tiles/pull/512) | 2026-06-14 | Raise Cilium stream idle timeout for ArgoCD UI |
| [511](https://github.com/symmatree/tiles/pull/511) | 2026-06-14 | Remove mavproxy liveness probe |
| [510](https://github.com/symmatree/tiles/pull/510) | 2026-06-14 | Run MAVProxy in daemon mode on acebase |
| [509](https://github.com/symmatree/tiles/pull/509) | 2026-06-13 | Fix mavproxy scheduling on acebase |
| [508](https://github.com/symmatree/tiles/pull/508) | 2026-06-13 | Add always-on MAVProxy ground hub for Rekon10 |
| [507](https://github.com/symmatree/tiles/pull/507) | 2026-06-13 | Fix RTKBase settings bind mount and always pull :main |
| [506](https://github.com/symmatree/tiles/pull/506) | 2026-06-13 | Update rtkbase to main |
| [505](https://github.com/symmatree/tiles/pull/505) | 2026-06-13 | Persist RTKBase settings on acebase NTRIP deployment |
| [492](https://github.com/symmatree/tiles/pull/492) | 2026-06-07 | Fix NTRIP bring-up: privileged namespace and gps/gps auth (#488) |
| [491](https://github.com/symmatree/tiles/pull/491) | 2026-06-07 | NTRIP Tanka deployment and Terraform secrets (issue #488 phases 3-4) |
| [490](https://github.com/symmatree/tiles/pull/490) | 2026-06-07 | Phase 2: RTKBase container image (issue #488) |
| [489](https://github.com/symmatree/tiles/pull/489) | 2026-06-07 | Phase 1: acebase GNSS Talos patch (issue #488) |
| [487](https://github.com/symmatree/tiles/pull/487) | 2026-06-07 | Add acebase as metal node |
| [486](https://github.com/symmatree/tiles/pull/486) | 2026-06-07 | Support intel bare-metal nodes |
| [485](https://github.com/symmatree/tiles/pull/485) | 2026-06-07 | spaces become dashes apparently |
| [484](https://github.com/symmatree/tiles/pull/484) | 2026-06-07 | push to prod as well as test |
| [481](https://github.com/symmatree/tiles/pull/481) | 2026-06-07 | Fix ha-ssh-sync SSH identity path for 1Password field names |
| [479](https://github.com/symmatree/tiles/pull/479) | 2026-06-07 | Sync Argo CD initial admin password to 1Password during bootstrap |
| [478](https://github.com/symmatree/tiles/pull/478) | 2026-06-07 | Use onepassword ssh secret type instead of a secure note |
| [476](https://github.com/symmatree/tiles/pull/476) | 2026-06-07 | Add run-name to operator workflows for clearer Actions list titles. |
| [475](https://github.com/symmatree/tiles/pull/475) | 2026-06-07 | Unnest env by one level |
| [474](https://github.com/symmatree/tiles/pull/474) | 2026-06-07 | More ram for application controller |
| [473](https://github.com/symmatree/tiles/pull/473) | 2026-06-07 | Fix wait for statefulset |
| [472](https://github.com/symmatree/tiles/pull/472) | 2026-06-07 | Fix stupid over-swallowing of output |
| [471](https://github.com/symmatree/tiles/pull/471) | 2026-06-06 | Taint more resources than just vms |
| [470](https://github.com/symmatree/tiles/pull/470) | 2026-06-06 | Ensure AppProject is installed before syncing app of apps. |
| [461](https://github.com/symmatree/tiles/pull/461) | 2026-05-25 | Higher limits |
| [460](https://github.com/symmatree/tiles/pull/460) | 2026-05-25 | Try limits dierctly in chart |
| [458](https://github.com/symmatree/tiles/pull/458) | 2026-05-25 | Fix Argo CD bootstrap to load per-cluster value files |
| [457](https://github.com/symmatree/tiles/pull/457) | 2026-05-25 | application-control spikes over 256 apparently |
| [456](https://github.com/symmatree/tiles/pull/456) | 2026-05-25 | Set prod memory requests more honestly, fix arrays not merged |
| [455](https://github.com/symmatree/tiles/pull/455) | 2026-05-25 | Multi-source value files for alloy, grafana, loki, argocd, cilium |
| [454](https://github.com/symmatree/tiles/pull/454) | 2026-05-24 | Extract Mimir values into multi-source Argo value files |
| [453](https://github.com/symmatree/tiles/pull/453) | 2026-05-24 | Oops 19.3 |
| [452](https://github.com/symmatree/tiles/pull/452) | 2026-05-24 | Reduce metrics volume and double-scraping |
| [451](https://github.com/symmatree/tiles/pull/451) | 2026-05-24 | Edge Alloy: prod-only OTLP and unified deploy flags |
| [450](https://github.com/symmatree/tiles/pull/450) | 2026-05-23 | force conflicts to get past a boostrap blocker |
| [449](https://github.com/symmatree/tiles/pull/449) | 2026-05-23 | fix(bond-mixin): repair Raconteur disk temperature PromQL |
| [448](https://github.com/symmatree/tiles/pull/448) | 2026-05-23 | Added config for proxmox mcp server |
| [447](https://github.com/symmatree/tiles/pull/447) | 2026-05-23 | Add bond-mixin with proxmox and raconetur temp alerts |
| [446](https://github.com/symmatree/tiles/pull/446) | 2026-05-23 | Update proxmox docs as-built following #442 |
| [444](https://github.com/symmatree/tiles/pull/444) | 2026-05-23 | Bump hashicorp/google from 7.32.0 to 7.33.0 in /tf/bootstrap |
| [442](https://github.com/symmatree/tiles/pull/442) | 2026-05-17 | fix(nodes): host_managed DHCP for Proxmox Alloy LXCs |
| [441](https://github.com/symmatree/tiles/pull/441) | 2026-05-17 | static-certs: deploy homeassistant-cert to HA Yellow over SSH |
| [440](https://github.com/symmatree/tiles/pull/440) | 2026-05-17 | Mimir: Set the timeInterval to fix rateInterval computation |
| [439](https://github.com/symmatree/tiles/pull/439) | 2026-05-16 | update tf lock |
| [437](https://github.com/symmatree/tiles/pull/437) | 2026-05-14 | fix(tf): pin Synology provider to 0.6.7 to unblock nodes apply |
| [434](https://github.com/symmatree/tiles/pull/434) | 2026-05-10 | fix(nodes): unix Alloy job relabel for node-exporter-mixin |
| [433](https://github.com/symmatree/tiles/pull/433) | 2026-05-10 | Grafana root_url for deeplinks; Synology monitoring doc refresh |
| [432](https://github.com/symmatree/tiles/pull/432) | 2026-05-10 | static-certs: push raconteur/cam/photos TLS to Synology DSM (prod) |
| [431](https://github.com/symmatree/tiles/pull/431) | 2026-05-09 | Proxmox Alloy instance label and node-exporter-mixin cluster dropdown |
| [430](https://github.com/symmatree/tiles/pull/430) | 2026-05-09 | kubernetes-mixin: drop spurious KubeProxyDown (Cilium) |
| [429](https://github.com/symmatree/tiles/pull/429) | 2026-05-09 | Alloy: integration-only scrape, alloy-mixin + cert-manager-mixin Argo |
| [428](https://github.com/symmatree/tiles/pull/428) | 2026-05-09 | Argo CD: allow postgres operator UI chart repo |
| [427](https://github.com/symmatree/tiles/pull/427) | 2026-05-09 | Argo CD: keep Tanka vendor cache in real dirs |
| [426](https://github.com/symmatree/tiles/pull/426) | 2026-05-09 | argocd: serialize Tanka CMP jb install with flock against shared cache |
| [425](https://github.com/symmatree/tiles/pull/425) | 2026-05-09 | Argo CD: bump controller -> repo-server gRPC deadline 60s -> 300s |
| [424](https://github.com/symmatree/tiles/pull/424) | 2026-05-09 | Remove fables submodule from tiles |
| [423](https://github.com/symmatree/tiles/pull/423) | 2026-05-09 | Argo CD: bump repo-server log level from debug to trace |
| [422](https://github.com/symmatree/tiles/pull/422) | 2026-05-09 | Argo CD: debug logs, repo-server ServiceMonitor, trace Tanka CMP plugin |
| [421](https://github.com/symmatree/tiles/pull/421) | 2026-05-09 | docs(readme): recreate cluster via taint-vms and nodes-plan-apply |
| [420](https://github.com/symmatree/tiles/pull/420) | 2026-05-07 | fix(bootstrap): rollout-operator CRD install URLs |
| [419](https://github.com/symmatree/tiles/pull/419) | 2026-05-07 | Update terraform deps. Planned and applied in bootstrap. |
| [414](https://github.com/symmatree/tiles/pull/414) | 2026-05-07 | fix(ci): scope nodes Terraform cache to tf/nodes lockfile |
| [413](https://github.com/symmatree/tiles/pull/413) | 2026-05-04 | fix(tf): Talos 1.13.0 for Image Factory + fables pointer |
| [412](https://github.com/symmatree/tiles/pull/412) | 2026-05-07 | Kubeconfig dev-setup, fables bump, submodule agent rule |
| [410](https://github.com/symmatree/tiles/pull/410) | 2026-05-04 | Bump bpg/proxmox from 0.102.0 to 0.105.0 in /tf/bootstrap |
| [409](https://github.com/symmatree/tiles/pull/409) | 2026-05-07 | Minor doc changes |
| [405](https://github.com/symmatree/tiles/pull/405) | 2026-05-04 | Bump hashicorp/google from 7.28.0 to 7.30.0 in /tf/bootstrap |
| [395](https://github.com/symmatree/tiles/pull/395) | 2026-04-19 | fix(cilium): L2 pod announcements interface pattern for 1.19 |
| [394](https://github.com/symmatree/tiles/pull/394) | 2026-05-07 | Argo CD: shared Jsonnet vendor cache, repo-server limits, calmer liveness |
| [393](https://github.com/symmatree/tiles/pull/393) | 2026-04-19 | Fix Postgres Operator UI chart, CoreDNS mixin selector, and offline Helm API versions |
| [386](https://github.com/symmatree/tiles/pull/386) | 2026-04-11 | docs: bootstrap-cluster runbook and fables bump |
| [385](https://github.com/symmatree/tiles/pull/385) | 2026-04-11 | fix(bootstrap): tag rulesets for CI deploy tags |
| [384](https://github.com/symmatree/tiles/pull/384) | 2026-04-11 | Talos 1.13.0-beta.1 pin, docs, rbac cleanup |
| [374](https://github.com/symmatree/tiles/pull/374) | 2026-05-07 | Bump 1password/load-secrets-action from 3 to 4 |
| [364](https://github.com/symmatree/tiles/pull/364) | 2026-04-11 | Bump ubiquiti-community/unifi from 0.41.3 to 0.41.25 in /tf/bootstrap |
| [362](https://github.com/symmatree/tiles/pull/362) | 2026-04-11 | tf/nodes: Proxmox Alloy LXC containers for host metrics and logs |
| [361](https://github.com/symmatree/tiles/pull/361) | 2026-03-11 | Bump hashicorp/google from 7.22.0 to 7.23.0 in /tf/nodes |
| [356](https://github.com/symmatree/tiles/pull/356) | 2026-03-07 | fables pointer update |
| [355](https://github.com/symmatree/tiles/pull/355) | 2026-03-07 | Add fables repo to bootstrap and refresh provider lockfiles |
| [352](https://github.com/symmatree/tiles/pull/352) | 2026-05-07 | Bump docker/metadata-action from 5 to 6 |
| [344](https://github.com/symmatree/tiles/pull/344) | 2026-04-11 | Bare-metal docs and metal-installer fix for Rising |
| [340](https://github.com/symmatree/tiles/pull/340) | 2026-03-02 | Bump hashicorp/google from 7.18.0 to 7.21.0 in /tf/nodes |
| [337](https://github.com/symmatree/tiles/pull/337) | 2026-05-07 | Bump hashicorp/setup-terraform from 3 to 4 |
| [322](https://github.com/symmatree/tiles/pull/322) | 2026-02-07 | proxmox only allows root@pam to do bind mounts |
| [321](https://github.com/symmatree/tiles/pull/321) | 2026-02-07 | Bump integrations/github from 6.10.2 to 6.11.0 in /tf/bootstrap |
| [320](https://github.com/symmatree/tiles/pull/320) | 2026-02-07 | Bump hashicorp/google from 7.17.0 to 7.18.0 in /tf/nodes |
| [319](https://github.com/symmatree/tiles/pull/319) | 2026-02-07 | Bump hashicorp/google from 7.17.0 to 7.18.0 in /tf/bootstrap |
| [318](https://github.com/symmatree/tiles/pull/318) | 2026-02-07 | Bump bpg/proxmox from 0.93.1 to 0.94.0 in /tf/nodes |
| [316](https://github.com/symmatree/tiles/pull/316) | 2026-02-07 | proxmox alloy exporter |
| [315](https://github.com/symmatree/tiles/pull/315) | 2026-02-01 | postgres-operator-ui and disable teams api explicitly |
| [314](https://github.com/symmatree/tiles/pull/314) | 2026-02-01 | postgres-operator install |
| [313](https://github.com/symmatree/tiles/pull/313) | 2026-01-31 | Update docs with actually-tested talosctl commands. |
| [312](https://github.com/symmatree/tiles/pull/312) | 2026-01-31 | Try moving argocd off the control plane |
| [311](https://github.com/symmatree/tiles/pull/311) | 2026-01-31 | Increase mimir limits |
| [310](https://github.com/symmatree/tiles/pull/310) | 2026-01-28 | Pin unifi, update other versions |
| [309](https://github.com/symmatree/tiles/pull/309) | 2026-01-28 | don't taint the node I took out of teh cluster |
| [304](https://github.com/symmatree/tiles/pull/304) | 2026-01-26 | Install coredns-mixin |
| [302](https://github.com/symmatree/tiles/pull/302) | 2026-01-26 | Use hostname not 127, specify auth here, remove labels for a minute |
| [301](https://github.com/symmatree/tiles/pull/301) | 2026-01-25 | Remove made-up fields for snmp-synology.yaml, remove taint on wk3 to … |
| [300](https://github.com/symmatree/tiles/pull/300) | 2026-01-25 | synology Alloy UI port |
| [299](https://github.com/symmatree/tiles/pull/299) | 2026-01-25 | Docs, use job_name aligned with k8s-monitoring-helm so we can reuse d… |
| [298](https://github.com/symmatree/tiles/pull/298) | 2026-01-25 | wrong service name for otlp catching |
| [297](https://github.com/symmatree/tiles/pull/297) | 2026-01-25 | Only export to tiles-test until it works |
| [296](https://github.com/symmatree/tiles/pull/296) | 2026-01-25 | Documentation for lots of components |
| [295](https://github.com/symmatree/tiles/pull/295) | 2026-01-25 | Remove made-up fields for node_exporter |
| [294](https://github.com/symmatree/tiles/pull/294) | 2026-01-25 | Fix and simplify alloy config for synology container |
| [293](https://github.com/symmatree/tiles/pull/293) | 2026-01-25 | try enabling receiver to get observability turned on |
| [292](https://github.com/symmatree/tiles/pull/292) | 2026-01-24 | do not set propagation mode on a root dir |
| [291](https://github.com/symmatree/tiles/pull/291) | 2026-01-24 | add snmp exporter to already nonfunctional setup |
| [290](https://github.com/symmatree/tiles/pull/290) | 2026-01-24 | deploy synology alloy in dev not prod while we test |
| [289](https://github.com/symmatree/tiles/pull/289) | 2026-01-24 | New repo for polisher project |
| [285](https://github.com/symmatree/tiles/pull/285) | 2026-01-22 | Also need to propagate it in github actions |
| [283](https://github.com/symmatree/tiles/pull/283) | 2026-01-22 | local certs are in a different project |
| [282](https://github.com/symmatree/tiles/pull/282) | 2026-01-22 | Static certs, local.symmatree.com dns privs |
| [281](https://github.com/symmatree/tiles/pull/281) | 2026-01-22 | Add lockfile |
| [279](https://github.com/symmatree/tiles/pull/279) | 2026-01-21 | Pin unifi provider to 0.41.3 to avoid breaking resource rename |
| [277](https://github.com/symmatree/tiles/pull/277) | 2026-01-19 | unifi provider needs password at plan time maybe |
| [276](https://github.com/symmatree/tiles/pull/276) | 2026-01-19 | unifi provider has different fields now |
| [275](https://github.com/symmatree/tiles/pull/275) | 2026-01-19 | Add doc index, remove lancer, update versions |
| [274](https://github.com/symmatree/tiles/pull/274) | 2026-01-19 | Update bootstrap versions all at once |
| [272](https://github.com/symmatree/tiles/pull/272) | 2026-01-17 | Fix odm jsonnet syntax |
| [270](https://github.com/symmatree/tiles/pull/270) | 2026-01-17 | Bump synology-community/synology from 0.6.7 to 0.6.9 in /tf/nodes |
| [265](https://github.com/symmatree/tiles/pull/265) | 2026-01-19 | Bump bpg/proxmox from 0.90.0 to 0.93.0 in /tf/bootstrap |
| [264](https://github.com/symmatree/tiles/pull/264) | 2026-01-11 | Alloy on nas, untested |
| [263](https://github.com/symmatree/tiles/pull/263) | 2026-01-10 | Alloy listening on otlp.clustername |
| [262](https://github.com/symmatree/tiles/pull/262) | 2026-01-10 | Make bootstrap more dependent |
| [261](https://github.com/symmatree/tiles/pull/261) | 2026-01-10 | Bump hashicorp/google from 7.14.1 to 7.15.0 in /tf/bootstrap |
| [258](https://github.com/symmatree/tiles/pull/258) | 2026-01-07 | Only set kernel args once |
| [257](https://github.com/symmatree/tiles/pull/257) | 2026-01-07 | Use real syntax for taints |
| [256](https://github.com/symmatree/tiles/pull/256) | 2026-01-07 | Start the VMs before deploying |
| [255](https://github.com/symmatree/tiles/pull/255) | 2026-01-07 | Lancer as worker in prod |
| [253](https://github.com/symmatree/tiles/pull/253) | 2026-01-05 | Back to talos provider hurray #186 |
| [252](https://github.com/symmatree/tiles/pull/252) | 2026-01-05 | two schematics, just output for now |
| [251](https://github.com/symmatree/tiles/pull/251) | 2026-01-04 | address some jsonnet issues so tk can build |
| [250](https://github.com/symmatree/tiles/pull/250) | 2026-01-04 | Add ODM node to actually do stuff, as well as initialization logic |
| [249](https://github.com/symmatree/tiles/pull/249) | 2026-01-04 | Remove overlay and other useless node exporter metrics |
| [248](https://github.com/symmatree/tiles/pull/248) | 2026-01-04 | Use correct tag not main |
| [247](https://github.com/symmatree/tiles/pull/247) | 2026-01-04 | Add VolumeSnapshot CRDs, update version stamps and remove trust-manag… |
| [246](https://github.com/symmatree/tiles/pull/246) | 2026-01-04 | More memory for first prod CP node |
| [245](https://github.com/symmatree/tiles/pull/245) | 2026-01-04 | Allocate another gig to CP nodes |
| [244](https://github.com/symmatree/tiles/pull/244) | 2026-01-03 | extraFoo doesn't work on singleBinary |
| [243](https://github.com/symmatree/tiles/pull/243) | 2026-01-03 | get rid of red herring SA |
| [242](https://github.com/symmatree/tiles/pull/242) | 2026-01-03 | Loki with explicit paths |
| [241](https://github.com/symmatree/tiles/pull/241) | 2026-01-03 | Fix nfs pv |
| [240](https://github.com/symmatree/tiles/pull/240) | 2026-01-03 | Change list of vars in bootstrap-cluster.yaml |
| [239](https://github.com/symmatree/tiles/pull/239) | 2026-01-03 | Remove last ServiceAccount token |
| [238](https://github.com/symmatree/tiles/pull/238) | 2026-01-03 | More robust attempt at #233 |
| [237](https://github.com/symmatree/tiles/pull/237) | 2026-01-03 | Add explicit dirs to get data out of the root. #233 |
| [236](https://github.com/symmatree/tiles/pull/236) | 2026-01-03 | Use a real parameter to fix #234 |
| [235](https://github.com/symmatree/tiles/pull/235) | 2026-01-03 | Increase Mimir rules per rule group limit to 50 |
| [232](https://github.com/symmatree/tiles/pull/232) | 2026-01-03 | Remove unconfigured on-deleted trigger from ArgoCD notifications |
| [230](https://github.com/symmatree/tiles/pull/230) | 2026-01-03 | Fix tfvars |
| [229](https://github.com/symmatree/tiles/pull/229) | 2026-01-03 | webodm and uniquify talos isos |
| [228](https://github.com/symmatree/tiles/pull/228) | 2026-01-03 | odm except for actual node |
| [227](https://github.com/symmatree/tiles/pull/227) | 2026-01-03 | Remove double-mounting of volumes, the ksonnet-util library does more… |
| [226](https://github.com/symmatree/tiles/pull/226) | 2026-01-02 | Fix typo in odm |
| [225](https://github.com/symmatree/tiles/pull/225) | 2026-01-02 | Add Postgres for ODM |
| [224](https://github.com/symmatree/tiles/pull/224) | 2026-01-02 | Loki tenant id is secure even if not |
| [223](https://github.com/symmatree/tiles/pull/223) | 2026-01-02 | Loki on 3100, nfs privileged |
| [222](https://github.com/symmatree/tiles/pull/222) | 2026-01-02 | Move loki off gateway |
| [221](https://github.com/symmatree/tiles/pull/221) | 2026-01-02 | Include /volume2 in nfs paths, ugh |
| [220](https://github.com/symmatree/tiles/pull/220) | 2026-01-02 | Try squash-all-users for nfs |
| [219](https://github.com/symmatree/tiles/pull/219) | 2026-01-02 | We finally read the docs |
| [218](https://github.com/symmatree/tiles/pull/218) | 2026-01-02 | Fix raconteur domain name, reduce mimir diffs |
| [217](https://github.com/symmatree/tiles/pull/217) | 2026-01-02 | Make loki use NFS and NFS use 4.1 |
| [216](https://github.com/symmatree/tiles/pull/216) | 2026-01-02 | While kafka cannot schedule no one else can |
| [215](https://github.com/symmatree/tiles/pull/215) | 2026-01-02 | Turns out it is array of vars not map |
| [214](https://github.com/symmatree/tiles/pull/214) | 2026-01-02 | Remove assertions that might be failing |
| [213](https://github.com/symmatree/tiles/pull/213) | 2026-01-02 | Remove unknown field from mimir |
| [212](https://github.com/symmatree/tiles/pull/212) | 2026-01-02 | NFS driver another way |
| [211](https://github.com/symmatree/tiles/pull/211) | 2026-01-02 | More RAM for control plane to handle NFS driver |
| [210](https://github.com/symmatree/tiles/pull/210) | 2026-01-02 | Talos cleanup, don't log secrets |
| [209](https://github.com/symmatree/tiles/pull/209) | 2026-01-02 | tanka rework, fixes for alloy and loki |
| [208](https://github.com/symmatree/tiles/pull/208) | 2026-01-02 | Fix loki and mimir, flatten some umbrella charts |
| [206](https://github.com/symmatree/tiles/pull/206) | 2026-01-01 | Take out env export again |
| [205](https://github.com/symmatree/tiles/pull/205) | 2026-01-01 | fix kubeconfig path and temporarily change to not use VIP |
| [204](https://github.com/symmatree/tiles/pull/204) | 2026-01-01 | Save talosconfig so I can try things manually |
| [203](https://github.com/symmatree/tiles/pull/203) | 2026-01-01 | Split talos to separate workflow for easier iteration |
| [202](https://github.com/symmatree/tiles/pull/202) | 2026-01-01 | Okay mayybe that won't fix it |
| [201](https://github.com/symmatree/tiles/pull/201) | 2026-01-01 | let the error messages through |
| [200](https://github.com/symmatree/tiles/pull/200) | 2026-01-01 | handle booting-needs-bootstrapped state |
| [199](https://github.com/symmatree/tiles/pull/199) | 2026-01-01 | Change retry logic |
| [198](https://github.com/symmatree/tiles/pull/198) | 2026-01-01 | Do not wait before but do afterwards |
| [197](https://github.com/symmatree/tiles/pull/197) | 2026-01-01 | Do not use VIP before creating it |
| [196](https://github.com/symmatree/tiles/pull/196) | 2025-12-31 | Try waiting first |
| [195](https://github.com/symmatree/tiles/pull/195) | 2025-12-31 | Set up talosconfig |
| [194](https://github.com/symmatree/tiles/pull/194) | 2025-12-31 | Remove overwrite of talos secret I'm now manually creating |
| [193](https://github.com/symmatree/tiles/pull/193) | 2025-12-31 | Maybe json better |
| [192](https://github.com/symmatree/tiles/pull/192) | 2025-12-31 | Actual machine secrets not whatever that was |
| [191](https://github.com/symmatree/tiles/pull/191) | 2025-12-31 | Auth talos script to talk to op |
| [190](https://github.com/symmatree/tiles/pull/190) | 2025-12-31 | Another conditional |
| [189](https://github.com/symmatree/tiles/pull/189) | 2025-12-31 | Fix gen secrets command line |
| [188](https://github.com/symmatree/tiles/pull/188) | 2025-12-31 | Talos is hard to please. |
| [187](https://github.com/symmatree/tiles/pull/187) | 2026-01-01 | Bump google-github-actions/auth from 2 to 3 |
| [185](https://github.com/symmatree/tiles/pull/185) | 2025-12-30 | Upgrade Talos, many charts |
| [184](https://github.com/symmatree/tiles/pull/184) | 2025-12-30 | Force version |
| [183](https://github.com/symmatree/tiles/pull/183) | 2025-12-30 | try to get project_id plumbed through again |
| [182](https://github.com/symmatree/tiles/pull/182) | 2025-12-30 | Disable pr-diff argocd for now |
| [176](https://github.com/symmatree/tiles/pull/176) | 2025-12-30 | Add GCP enterprise foundation with OIDC workload identity |
| [173](https://github.com/symmatree/tiles/pull/173) | 2025-12-27 | Add ArgoCD diff rendering for PRs with checked-in rendered manifests |
| [172](https://github.com/symmatree/tiles/pull/172) | 2025-12-27 | Even less auth |
| [171](https://github.com/symmatree/tiles/pull/171) | 2025-12-27 | Fix loki-data-source |
| [170](https://github.com/symmatree/tiles/pull/170) | 2025-12-27 | disable auth but keep enable_auth |
| [169](https://github.com/symmatree/tiles/pull/169) | 2025-12-25 | Ugh helm arrays do not merge |
| [168](https://github.com/symmatree/tiles/pull/168) | 2025-12-25 | Loki basic auth changes |
| [167](https://github.com/symmatree/tiles/pull/167) | 2025-12-25 | Bump bpg/proxmox from 0.89.1 to 0.90.0 in /tf/nodes |
| [166](https://github.com/symmatree/tiles/pull/166) | 2025-12-25 | Bump bpg/proxmox from 0.89.1 to 0.90.0 in /tf/bootstrap |
| [164](https://github.com/symmatree/tiles/pull/164) | 2025-12-22 | add tenantid field to loki secret |
| [163](https://github.com/symmatree/tiles/pull/163) | 2025-12-22 | loki htpasswd not htaccess |
| [162](https://github.com/symmatree/tiles/pull/162) | 2025-12-22 | mimir gateway so grafana is happy |
| [161](https://github.com/symmatree/tiles/pull/161) | 2025-12-22 | localLoki auth again |
| [160](https://github.com/symmatree/tiles/pull/160) | 2025-12-21 | localLoki auth changes |
| [159](https://github.com/symmatree/tiles/pull/159) | 2025-12-21 | Just drop initchown container |
| [158](https://github.com/symmatree/tiles/pull/158) | 2025-12-21 | mimir datasource ports, loki datasource auth |
| [157](https://github.com/symmatree/tiles/pull/157) | 2025-12-21 | Assert vars in a different way |
| [156](https://github.com/symmatree/tiles/pull/156) | 2025-12-21 | Fix param propagation in argocd |
| [155](https://github.com/symmatree/tiles/pull/155) | 2025-12-21 | Fix assertion in main |
| [154](https://github.com/symmatree/tiles/pull/154) | 2025-12-21 | add params to tanka applications |
| [153](https://github.com/symmatree/tiles/pull/153) | 2025-12-21 | Pass along real var if set |
| [151](https://github.com/symmatree/tiles/pull/151) | 2025-12-21 | Factor out variable-setting for consistency and required-satisfaction |
| [150](https://github.com/symmatree/tiles/pull/150) | 2025-12-21 | Move app project to argocd so we can single-resource the app-of-apps |
| [149](https://github.com/symmatree/tiles/pull/149) | 2025-12-21 | Try alternate multiline command syntax |
| [148](https://github.com/symmatree/tiles/pull/148) | 2025-12-21 | Try alternate multiline command syntax |
| [147](https://github.com/symmatree/tiles/pull/147) | 2025-12-21 | Fix cwd assumption in argocd-applications/install-application.sh |
| [146](https://github.com/symmatree/tiles/pull/146) | 2025-12-21 | Refactor bootstrap, better rendered.yaml, options for bootstrap steps… |
| [145](https://github.com/symmatree/tiles/pull/145) | 2025-12-21 | Only name and value in the invocation |
| [143](https://github.com/symmatree/tiles/pull/143) | 2025-12-21 | Fix structure of yaml-within-string for config plugin |
| [142](https://github.com/symmatree/tiles/pull/142) | 2025-12-21 | Make git available |
| [141](https://github.com/symmatree/tiles/pull/141) | 2025-12-21 | Tanka parameters explicit in application.yaml |
| [140](https://github.com/symmatree/tiles/pull/140) | 2025-12-21 | Cilium non-dupe |
| [139](https://github.com/symmatree/tiles/pull/139) | 2025-12-21 | Mixins for several systems |
| [138](https://github.com/symmatree/tiles/pull/138) | 2025-12-21 | Bump hashicorp/google from 7.13.0 to 7.14.1 in /tf/nodes |
| [137](https://github.com/symmatree/tiles/pull/137) | 2025-12-21 | Bump hashicorp/google from 7.13.0 to 7.14.1 in /tf/bootstrap |
| [134](https://github.com/symmatree/tiles/pull/134) | 2025-12-14 | Fix context directory for buildah |
| [133](https://github.com/symmatree/tiles/pull/133) | 2025-12-14 | Use latest :main image for webhook |
| [132](https://github.com/symmatree/tiles/pull/132) | 2025-12-14 | Fix webhook-build paths |
| [131](https://github.com/symmatree/tiles/pull/131) | 2025-12-14 | Fewer argo notifications |
| [130](https://github.com/symmatree/tiles/pull/130) | 2025-12-14 | Fix notifications-cm for mimir, webhook building iteration |
| [129](https://github.com/symmatree/tiles/pull/129) | 2025-12-14 | ArgoCD notify |
| [128](https://github.com/symmatree/tiles/pull/128) | 2025-12-14 | AppRise and Mimir |
| [127](https://github.com/symmatree/tiles/pull/127) | 2025-12-14 | Bump actions/cache from 4 to 5 |
| [126](https://github.com/symmatree/tiles/pull/126) | 2025-12-14 | Bump hashicorp/google from 7.12.0 to 7.13.0 in /tf/nodes |
| [125](https://github.com/symmatree/tiles/pull/125) | 2025-12-14 | Bump hashicorp/google from 7.12.0 to 7.13.0 in /tf/bootstrap |
| [120](https://github.com/symmatree/tiles/pull/120) | 2025-12-14 | Bump integrations/github from 6.8.3 to 6.9.0 in /tf/bootstrap |
| [119](https://github.com/symmatree/tiles/pull/119) | 2025-12-08 | Use tenants to query mimir and loki, with passwrd for loki |
| [118](https://github.com/symmatree/tiles/pull/118) | 2025-12-08 | data sources for loki and mimir |
| [117](https://github.com/symmatree/tiles/pull/117) | 2025-12-08 | Tenants for alloy |
| [116](https://github.com/symmatree/tiles/pull/116) | 2025-12-07 | Conservatively skip on changes only to charts/ |
| [115](https://github.com/symmatree/tiles/pull/115) | 2025-12-07 | Alloy (or rather k8s-monitoring) |
| [114](https://github.com/symmatree/tiles/pull/114) | 2025-12-07 | Explicit name servers and get on with life |
| [113](https://github.com/symmatree/tiles/pull/113) | 2025-12-07 | Do not worry about cert-manager clutter in DNS |
| [112](https://github.com/symmatree/tiles/pull/112) | 2025-12-07 | init-chown container with different creds |
| [111](https://github.com/symmatree/tiles/pull/111) | 2025-12-07 | We do need the token for reals |
| [110](https://github.com/symmatree/tiles/pull/110) | 2025-12-07 | Fix vault name for grafana secrets |
| [109](https://github.com/symmatree/tiles/pull/109) | 2025-12-07 | Doc cleanup and maybe debug logging |
| [108](https://github.com/symmatree/tiles/pull/108) | 2025-12-07 | Remove kubeconfig dependency |
| [107](https://github.com/symmatree/tiles/pull/107) | 2025-12-07 | Set git username before pushing a change |
| [105](https://github.com/symmatree/tiles/pull/105) | 2025-12-07 | push-to-tag, terraform workspaces |
| [104](https://github.com/symmatree/tiles/pull/104) | 2025-12-06 | Grafana deployment for tiles |
| [103](https://github.com/symmatree/tiles/pull/103) | 2025-12-06 | Remove retry config because they refuse it |
| [102](https://github.com/symmatree/tiles/pull/102) | 2025-12-06 | Nest gcs deeper in mimir config |
| [101](https://github.com/symmatree/tiles/pull/101) | 2025-12-06 | More CPU and RAM for teh control plane |
| [100](https://github.com/symmatree/tiles/pull/100) | 2025-12-06 | Mimir: Be more explicit about GCS to maybe fix no s3 endpoint in conf… |
| [99](https://github.com/symmatree/tiles/pull/99) | 2025-12-06 | Bump hashicorp/kubernetes from 2.38.0 to 3.0.0 in /tf/nodes |
| [98](https://github.com/symmatree/tiles/pull/98) | 2025-12-02 | Drop mimir cpu requests so it schedules more |
| [97](https://github.com/symmatree/tiles/pull/97) | 2025-12-02 | Bump bpg/proxmox from 0.87.0 to 0.88.0 in /tf/bootstrap |
| [96](https://github.com/symmatree/tiles/pull/96) | 2025-12-02 | Bump bpg/proxmox from 0.87.0 to 0.88.0 in /tf/nodes |
| [95](https://github.com/symmatree/tiles/pull/95) | 2025-12-01 | CRD version extraction for helm templating |
| [94](https://github.com/symmatree/tiles/pull/94) | 2025-12-01 | Mimir k8s-side configuration |
| [93](https://github.com/symmatree/tiles/pull/93) | 2025-12-01 | Add mimir TF config |
| [92](https://github.com/symmatree/tiles/pull/92) | 2025-11-30 | Try to fix anti-affinity |
| [91](https://github.com/symmatree/tiles/pull/91) | 2025-11-30 | Fix namespace from the weird name cursor chose |
| [90](https://github.com/symmatree/tiles/pull/90) | 2025-11-30 | Set namespace metadata for local-path |
| [89](https://github.com/symmatree/tiles/pull/89) | 2025-11-30 | Template and rendered output |
| [88](https://github.com/symmatree/tiles/pull/88) | 2025-11-30 | local-path-provisioner for storage |
| [87](https://github.com/symmatree/tiles/pull/87) | 2025-11-30 | Fix vault paths I think |
| [86](https://github.com/symmatree/tiles/pull/86) | 2025-11-30 | Fix volume syntax |
| [85](https://github.com/symmatree/tiles/pull/85) | 2025-11-30 | Propagate more env to helm |
| [84](https://github.com/symmatree/tiles/pull/84) | 2025-11-30 | Update comments in-place, iterate on loki |
| [83](https://github.com/symmatree/tiles/pull/83) | 2025-11-30 | privs changes and enable KMS |
| [82](https://github.com/symmatree/tiles/pull/82) | 2025-11-30 | Loki TF and chart |
| [81](https://github.com/symmatree/tiles/pull/81) | 2025-11-29 | Tear out oidc client and maybe fix dex |
| [80](https://github.com/symmatree/tiles/pull/80) | 2025-11-29 | Use a shorter id for the credential |
| [79](https://github.com/symmatree/tiles/pull/79) | 2025-11-29 | Use the right id for the client credential |
| [78](https://github.com/symmatree/tiles/pull/78) | 2025-11-29 | add client_type |
| [77](https://github.com/symmatree/tiles/pull/77) | 2025-11-29 | Bootstrap rights instead of trying to self-grant |
| [76](https://github.com/symmatree/tiles/pull/76) | 2025-11-29 | Grant ourselves rights to create an oauth client |
| [75](https://github.com/symmatree/tiles/pull/75) | 2025-11-29 | Okay this is more likely |
| [74](https://github.com/symmatree/tiles/pull/74) | 2025-11-29 | Try capitals |
| [73](https://github.com/symmatree/tiles/pull/73) | 2025-11-29 | OAuth client for argocd login-with-google |
| [72](https://github.com/symmatree/tiles/pull/72) | 2025-11-29 | Temporarily remove cert-manager override |
| [70](https://github.com/symmatree/tiles/pull/70) | 2025-11-29 | Also force using them I guess |
| [69](https://github.com/symmatree/tiles/pull/69) | 2025-11-29 | Try to force cert-manager dns |
| [68](https://github.com/symmatree/tiles/pull/68) | 2025-11-29 | Try to force cert-manager dns |
| [67](https://github.com/symmatree/tiles/pull/67) | 2025-11-29 | Grant project-level dns reader |
| [66](https://github.com/symmatree/tiles/pull/66) | 2025-11-29 | quality of life |
| [65](https://github.com/symmatree/tiles/pull/65) | 2025-11-28 | Denoise DNS and add a todo doc |
| [64](https://github.com/symmatree/tiles/pull/64) | 2025-11-28 | Cert-manager: Another template in the values |
| [63](https://github.com/symmatree/tiles/pull/63) | 2025-11-28 | Use Cloudflare provider to set up dns delegation to Cloud DNS |
| [62](https://github.com/symmatree/tiles/pull/62) | 2025-11-27 | Grant project-level dns reader and also fix quoting |
| [61](https://github.com/symmatree/tiles/pull/61) | 2025-11-27 | values.yaml is NOT template-expanded, push values in from application… |
| [60](https://github.com/symmatree/tiles/pull/60) | 2025-11-24 | Mask the encoded credentials and do not log them |
| [59](https://github.com/symmatree/tiles/pull/59) | 2025-11-24 | Initial shot at external-dns |
| [58](https://github.com/symmatree/tiles/pull/58) | 2025-11-23 | Fix the name of the secret issuer to be interpolated |
| [57](https://github.com/symmatree/tiles/pull/57) | 2025-11-23 | trust-manager on control plane so its webhook is available |
| [56](https://github.com/symmatree/tiles/pull/56) | 2025-11-23 | Avoid the need to escape secret values |
| [55](https://github.com/symmatree/tiles/pull/55) | 2025-11-23 | Initial onepassword install |
| [54](https://github.com/symmatree/tiles/pull/54) | 2025-11-23 | Pass onepassword vault name to output not uuid |
| [53](https://github.com/symmatree/tiles/pull/53) | 2025-11-23 | Install gateway api CRDs for cilium and cert-manager |
| [52](https://github.com/symmatree/tiles/pull/52) | 2025-11-23 | Force conflicts on the applications |
| [51](https://github.com/symmatree/tiles/pull/51) | 2025-11-23 | Failing on split-owners, only apply when missing |
| [50](https://github.com/symmatree/tiles/pull/50) | 2025-11-23 | Use real not kubens |
| [49](https://github.com/symmatree/tiles/pull/49) | 2025-11-23 | Setup helm not terraform for bootstrap |
| [48](https://github.com/symmatree/tiles/pull/48) | 2025-11-23 | Stay in root dir |
| [47](https://github.com/symmatree/tiles/pull/47) | 2025-11-23 | I also deleted teh PROJECT_ID secret |
| [46](https://github.com/symmatree/tiles/pull/46) | 2025-11-23 | Claude wrongly thinks we can put static variables in a load-secrets b… |
| [45](https://github.com/symmatree/tiles/pull/45) | 2025-11-23 | vault_name in misc-config and explain to claude why we cannot change … |
| [44](https://github.com/symmatree/tiles/pull/44) | 2025-11-23 | Load a kubeconfig from 1password |
| [43](https://github.com/symmatree/tiles/pull/43) | 2025-11-23 | Fix cilium cluster_id as string |
| [42](https://github.com/symmatree/tiles/pull/42) | 2025-11-22 | Add DNS IAM privs to TF SA |
| [40](https://github.com/symmatree/tiles/pull/40) | 2025-11-22 | Log versions and files to try to understand build problem |
| [39](https://github.com/symmatree/tiles/pull/39) | 2025-11-22 | cert-manager service account |
| [38](https://github.com/symmatree/tiles/pull/38) | 2025-11-23 | Bump actions/checkout from 5 to 6 |
| [32](https://github.com/symmatree/tiles/pull/32) | 2025-11-23 | Bump integrations/github from 6.7.5 to 6.8.3 in /tf/bootstrap |
| [31](https://github.com/symmatree/tiles/pull/31) | 2025-11-16 | Fix project consistency |
| [28](https://github.com/symmatree/tiles/pull/28) | 2025-11-16 | Switch to almost-exclusively 1password resources |
| [24](https://github.com/symmatree/tiles/pull/24) | 2025-11-11 | Fix control plane network |
| [23](https://github.com/symmatree/tiles/pull/23) | 2025-11-09 | Decompose and try to figure it out |
| [19](https://github.com/symmatree/tiles/pull/19) | 2025-11-01 | Try to bootstrap |
| [18](https://github.com/symmatree/tiles/pull/18) | 2025-11-01 | Bump integrations/github from 6.7.1 to 6.7.3 in /tf/bootstrap |
| [16](https://github.com/symmatree/tiles/pull/16) | 2025-11-01 | Bump hashicorp/google from 7.8.0 to 7.9.0 in /tf/bootstrap |
| [14](https://github.com/symmatree/tiles/pull/14) | 2025-11-01 | Use halt_if_installed |
| [13](https://github.com/symmatree/tiles/pull/13) | 2025-10-28 | Fix nodes name |
| [11](https://github.com/symmatree/tiles/pull/11) | 2025-10-25 | Talos bootstrap, Factor out actions |
| [7](https://github.com/symmatree/tiles/pull/7) | 2025-10-22 | network ranges, machine config stubout |
| [6](https://github.com/symmatree/tiles/pull/6) | 2025-11-01 | Bump actions/checkout from 4 to 5 |
| [5](https://github.com/symmatree/tiles/pull/5) | 2025-10-20 | Get rid of github secrets and unused variables |
| [4](https://github.com/symmatree/tiles/pull/4) | 2025-10-20 | Use onepassword directly for secrets |
| [3](https://github.com/symmatree/tiles/pull/3) | 2025-10-19 | Fixed port for unifi |
| [2](https://github.com/symmatree/tiles/pull/2) | 2025-10-15 | Add VMs, tf-plan infra |
| [1](https://github.com/symmatree/tiles/pull/1) | 2025-10-07 | Init bootstrap and nodes, no VMs yet |

## Themes

- Terraform/Infrastructure (~61 PRs)
- Observability/Monitoring (~50 PRs)
- Bare-metal/Talos (~35 PRs)
- GitOps/ArgoCD (~29 PRs)
- Security/Auth (~23 PRs)
- Networking/DNS (~14 PRs)
- JupyterHub/Datascience (~10 PRs)
- Kubernetes/Cluster (~10 PRs)
- Documentation (~9 PRs)
- Container/Images (~8 PRs)
