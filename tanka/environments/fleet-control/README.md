# fleet-control

Ground-station control surface for the rekon10 fleet: converge a node, read what each is
running, and pull a flight's captures off the cards -- from a phone, over SSH, driven from the
cluster.

**What the service is and does is documented with the service**, in
[`coordinator/containers/fleet-control/README.md`](https://github.com/symmatree/coordinator/tree/main/containers/fleet-control)
-- the routes, the image and the run log. That is where it changes, so that is
where it is described; **this file is the deployment only.** A copy of it here goes stale
without anyone noticing, which is exactly what happened: this README described `bootstrap` and
`update` actions running `./host/one_time.sh` for months after
[coordinator#263](https://github.com/symmatree/coordinator/pull/263) replaced both with one
`converge` and deleted the script.

| | |
|---|---|
| Web UI / API | `https://fleet.{cluster}.symmatree.com` -- a private **10.x** address on site LAN, no public exposure |
| Image | `ghcr.io/symmatree/coordinator-fleet-control:main` |
| Source | [`coordinator/containers/fleet-control`](https://github.com/symmatree/coordinator/tree/main/containers/fleet-control) |
| Tanka | [`main.jsonnet`](main.jsonnet), settings in [`application.yaml`](application.yaml) |
| Argo CD | [`fleet-control-application.helm.yaml`](../../../charts/argocd-applications/templates/fleet-control-application.helm.yaml) (prod only) |
| Issues | coordinator [#236](https://github.com/symmatree/coordinator/issues/236), [#223](https://github.com/symmatree/coordinator/issues/223) |

Prod (`tiles`) only: it converges the fleet, and the fleet SSH key has exactly one writer.

## Two credentials, both from 1Password

The Deployment mounts a private key and reads a token; **it will not start without the key.**
Both items must exist in the `tiles-secrets` vault before the first sync.

| | item | field | |
|---|---|---|---|
| fleet SSH key | `fleet-ssh-key-managed` (SSH Key) | `private-key` | created by `tf/nodes/fleet-ssh-key.tf`; mounted at `/secrets/ssh/id` |
| GitHub token | `FLEET_GITHUB_TOKEN` (Login) | `password` | *Actions: read-only*, fine-grained |

Unprefixed: there is one fleet and one key, and `onepassword_vault_name` comes from
`terraform.tfvars` rather than per workspace, so the name is not qualified by cluster and must not
be written from more than one place -- see `tf/nodes/fleet-ssh-key.tf`. The item names are
parameters: point them at an item that exists rather than copying a key into a new one.

The operator lowercases field labels and replaces spaces with hyphens, which is why an SSH Key
item's *private key* field arrives as `private-key`. The 1Password *title* `FLEET_GITHUB_TOKEN`
is not a legal Kubernetes object name (DNS-1123: lowercase, no underscores), so the item path
keeps the title and the object gets a derived one.

**The SSH key is root on the whole fleet.** `pi` has passwordless sudo on every node, so
anything that can log in can do anything. That is a property of the fleet, not of this service;
coordinator [#261](https://github.com/symmatree/coordinator/issues/261) proposes giving
automation its own revocable key. The **token is not**: it can fetch published build artifacts
and nothing else, and every route except the image fetch works without it.

The matching **public** key must be `SSH_PUBKEY` in `dotfiles-symm/pi-image/provision/fleet.env`,
so a freshly flashed card trusts it on first boot.

## The roster

[`inventory.json`](inventory.json) is the source of truth, mounted at `/config/inventory.json`.
Editing it changes the pod-template hash annotation, so Argo rolls the Deployment and the change
lands on the next sync -- no manual step.

Each node takes a `name`, a `role`, and an optional `host` (an address or a different hostname)
defaulting to `name`. The `host` values are current DHCP leases and need updating when one
moves; [#735](https://github.com/symmatree/tiles/issues/735) makes them reservations, after
which the names resolve and `host` can come out. `campod-ne` and `campod-nw` are listed without
one because they have not been flashed.

## Volumes

| mount | claim | why that class |
|---|---|---|
| `/mnt/flights` | 2Ti, static NFS PV, `Retain` | where recovered flights land. `FLEET_FLIGHTS_DIR` points at `/mnt/flights/rekon10`, the platform level, because the service joins only the flight name it is given and `flight-data-layout.md` is `flights/<platform>/<flight>/`. A static PV because the datasets share (`datasets_nfs_path`, per cluster) is a different export from the one `cluster-nfs` provisions into, so a dynamic claim cannot reach it -- same pattern and subpath as `flight-analysis` and `vio-offline`. `Retain`, because this holds the only copy of a flight once the device is wiped |
| `/mnt/ground-tlogs` | 200Gi, static NFS PV | the per-flight tlogs `tlog-split` writes (in the mavproxy environment), read by the ground collect. Static for the same reason as the flights share |

The image runs as `node` (uid/gid 1000) and Secret volumes are root-owned, so `fsGroup: 1000`
is what makes the 0440 key readable by the process that needs it.

## Lifecycle

What a pod restart costs is the service's to say, and changes with it -- see "Known
limitations" in the
[service README](https://github.com/symmatree/coordinator/tree/main/containers/fleet-control).
Since [coordinator#504](https://github.com/symmatree/coordinator/issues/504) a playbook run or
a collect is a workflow and outlives the pod; stop, reboot and ground still run in it.

- **`Recreate`, not `RollingUpdate`.** The per-node lock is partly held in the service's memory
  ([coordinator#566](https://github.com/symmatree/coordinator/issues/566) removes that), so two
  replicas would be two locks.
- **No liveness probe.** Readiness only. The reason recorded for it -- a converge running in
  this process for twenty minutes -- went with coordinator#504.
- **`roll-on-digest-change: true`**, opting in to
  [argo-tag-watcher](../../../containers/argo-tag-watcher/README.md)'s image side. The image is
  a floating `:main` tag, so a rebuild moves the digest without changing the string here and
  nothing would otherwise roll the pod. The playbook is **not** in this image: a playbook step
  fetches it as a published artifact at run time, so an ansible change needs no roll.

## Fleet operations run as Argo Workflows

How the service submits and follows them is in the
[service README](https://github.com/symmatree/coordinator/tree/main/containers/fleet-control);
this section is the declared half.

| template | submitted by | |
|---|---|---|
| `fleet-control-playbook` | the service: converge, provision | [coordinator#504](https://github.com/symmatree/coordinator/issues/504) |
| `fleet-control-collect` | the service: `POST /flights/:flight/collect` | [coordinator#566](https://github.com/symmatree/coordinator/issues/566), below |
| `bench-simflight` | `argo submit`, by whoever runs the bench | [coordinator#541](https://github.com/symmatree/coordinator/pull/541), below |

Beside them, a ServiceAccount for the workflows' pods and two Roles.

**`fleet-control-playbook` covers every playbook run** — converge and full provision are
the same step with a different `playbook` parameter, plus `extra-vars` for whatever that
playbook needs beyond `device_role`. `extra-vars` is a JSON object, empty by
default; the step merges it into the vars the play is given and refuses any key that would
displace the four it sets itself, since those are how the play reaches the device and what
key it installs there.

### Why a template rather than a Workflow built in code

A `WorkflowTemplate` is a definition, so it is reviewable in git; what the service submits is
a reference to it plus parameters. That is only possible because the Argo CRDs are installed
by `tf/nodes/k8s-bootstrap.tf`, ahead of the Argo CD tree — Argo CD cannot diff a resource
whose type it does not know. See [#827](https://github.com/symmatree/tiles/issues/827).

The step's body is `run-playbook.sh` out of the service's own image. Whether that script
belongs in that image is an open question; moving it changes `image` and `command` here and
nothing else.

### Why in this namespace

Everything a converge needs is already here: the fleet key, the GitHub token, the roster.
Running workflows in a central namespace would mean a second copy of the fleet key in a
second namespace, and one key with two homes is how this service came to present a key no
device trusted.

`FLEET_SSH_PUBLIC_KEY` is the `public-key` field of the **same 1Password item** that holds
`private-key`; `charts/jupyterhub` consumes its own ssh-key item the same way. Terraform
generates the pair and writes both fields together.

### Why two Roles

| Role | grants | to |
|---|---|---|
| `fleet-control-workflow` | `workflowtaskresults` create, patch | the workflow's **pods** |
| `fleet-control-submit` | `workflows` create/get/list/watch/delete, `pods` + `pods/log` read | the **service** |

Argo's executor reports each step's outcome by writing a `workflowtaskresult`, so a pod needs
that much. This is why a namespace that runs workflows carries a little RBAC of its own
rather than inheriting the controller's, which is cluster-wide and comes with the chart.

The service's half is submitting and then finding its workflow again — **by label, not by an
id held in memory**, so that a pod roll does not orphan a workflow that is still running.
That is the property the whole change exists to buy.

In Kubernetes terms the workflow pod is nearly unprivileged: two verbs on one resource. Its
reach comes from the mounted fleet key, which is root on every device.

### No `activeDeadlineSeconds`

Deliberate. A previous version of the service imposed a 60-minute ceiling, hit it on a slow
node, and reported a successful converge as a failure while the play was still running.
Killing a play half-way leaves a part-configured box. Ansible's own timeouts bound it.

### `ttlStrategy: 7 days`

There is no workflow archive ([#831](https://github.com/symmatree/tiles/pull/831)), so the
`Workflow` object *is* the run record and this is how far back the API can answer "what ran".
The log outlives it either way: Alloy ships the step's stdout to Loki.

## Collecting a flight

[coordinator#566](https://github.com/symmatree/coordinator/issues/566). `fleet-control-collect`
is one step per thing retrieved, fanned out with `withParam` over a `targets` parameter.
There is nothing after them. Why the bytes moved out of the service, with the before-and-after
timings, is in the service README's "Collecting a flight".

### One step template, both kinds

A target is `{node, kind, id}` whatever it is -- `kind` is `session` or `fc-log` -- so the
fan-out spreads both into the same step and there is no second template to keep in step with
the first. They were separate routes run in sequence before, which put a ~30-minute dataflash
pull behind the campods for no reason: they are different devices.

### Two of one kind on one device take turns

The step holds a mutex named for its node and kind. FC logs are pulled over the
coordinator's one UART, and two readers on it each get part of the byte stream: on
2026-10-25 three fc-log steps on the coordinator started together and two failed with
pyserial's "device reports readiness to read but returned no data". Keyed on kind as well, so
a coordinator session -- 15 s each that day -- does not wait behind a 25-minute log; the price
is that two sessions on one node also take turns. Argo mutexes are namespace-wide, so it holds
across collect workflows too.

### The flights PVC, mounted by the steps

This is the one template whose steps need the datasets share. It is `ReadWriteMany` NFS, which
is what lets two step pods on different nodes write into one flight directory at the same
time; the playbook steps mount nothing.

### Why there is no join step

Each offload writes its own file under the flight's `collected/`, so nothing has to be
merged. The alternative was a single `flight.json` appended to by both steps -- which is
read-modify-write across two pods, loses whichever entry was read before the other's write,
and then needs a join step to reconcile what it lost. Dropping the shared file drops all of
it: the reader globs the directory.

A flight short one campod is a directory with one file in it, which is what being short one
looks like.

### `imagePullPolicy: Always`, as for the bench steps

Same reason, and it holds for every template here: `:main` floats, so Kubernetes defaults to
`IfNotPresent` and a node with a stale cached layer runs old code, with no tag watcher to
correct it the way the Deployment has.

## The bench simulated-flight cycle

[coordinator#541](https://github.com/symmatree/coordinator/pull/541). `bench-simflight` is
the camera-sync test procedure on the bench rig, declared. It was a local python script run
by hand, and the cycle drifted trial to trial -- a wait skipped, a different window length,
a flight name that did not match the session that got collected -- which is exactly the
variable you cannot have in a timing measurement. The steps now come from one definition:

    argo submit --from workflowtemplate/bench-simflight -n fleet-control \
        -p flight=bench-20261017-simflight-11

The steps are `deploy`, `arm`, `window`, `disarm` and `collect`, in that order. All but
`window` run a stage of
[`harness/bench_cycle.py`](https://github.com/symmatree/coordinator/blob/main/harness/bench_cycle.py)
(`bench-cycle` in the service's image), and **what each stage does and waits for is documented
there**, where it changes. `window` is a `suspend`, `window-seconds` long (default 240).

**Whether the code under test is built is the caller's business, not the workflow's.** An
earlier version checked that the service was serving the newest commit and that the camera
image's build job had succeeded before it would converge, which is the stack's provenance
re-derived from outside it -- and wrong for the common case, where the operator knows
perfectly well whether they are waiting on a build. Submit it when you want it to run; what
ran is recorded in each session's `manifests/` afterwards.

The step body is `bench-cycle` out of the service's image, for the same reasons
`run-playbook.sh` is: it needs that image's python and ssh client, and it drives this
service's own API. Arming is the one step that touches a device directly -- the arm file has
no API verb -- so the steps mount the fleet key.

### The window is a `suspend` step

Not a sleep in a container. A suspended step has no pod, so during the measurement nothing
of ours is scheduled, logging, or polling. The pods are 417 MiB boards and the thing under
test is frame timing; a poll that evicts the camera's working set is a poll that changes the
measurement.

### `activeDeadlineSeconds: 5400`, unlike the playbook template

The reason that one has none does not apply here. This workflow holds the rig **armed**
between two of its steps, so a cycle that hangs holds it armed indefinitely, filling cards
with frames no trial will use. 90 minutes is generous for two converges, three reboots and
a four-minute window.

`onExit: disarm` runs the disarm step whatever happened, so a failure or a stop mid-window
does not leave the rig armed with the FC talker stopped. Writing `0` twice is what the
device already expects.

### No `retryStrategy`

A failed converge or a missed `ready` means the fleet is not in the state the trial assumes.
Retrying against a device that is mid-reboot produces a trial whose conditions nobody knows,
which is worse than no trial.

## Auth

None. On-network only, like the other private-address services here. If it is ever wanted
remotely it should be fronted with oauth-proxy, per coordinator#223.
