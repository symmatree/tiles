# Overview

## Fundamental Why

The basic "why" is that I have spent a lot of my adult life haphazardly maintaining a
computing system, whether a single machine or a network or a NAS or just a bunch of
Chromebooks. Thanks to varying interests, jobs, and general demands of life, this has
often been a burst of activity to get to a reasonable point, then genteel decay until
something breaks decisively or until I get a new enthusiasm. This has been accompanied by a long series of Google docs and various
internal wiki writeups of "the current config", mostly in the form of trying to
rediscover what I had been trying to do last time.

Along the way I've tried many different technical approaches to capture and maintain the state
of systems, so I can recreate or repair it when the time comes.

* A subversion-derived tool called `fsvs` to version a server's `/etc` directory
* Long notes about what I clicked in various UIs
* Lots of docker containers on a Synology box, with config mixed between on-disk and
  checked-in
* docker-compose recipes to try to orchestrate and coordinate multiple services
* virtual machines on the Synology box running Talos Linux to provide a Kubernetes cluster

A common thread is that they all required me to go pretty far off-script, since these weren't
really the mainstream ways people use these tools. For example, I ended up installing a more
modern version of `docker-compose` on the Synology, which let me do what I wanted but also
made the whole system more brittle and more likely to require ongoing maintenance.

Without getting into a separate essay, a growing theme for me has to been to stay near the
brightly-lit path, simply because it is more likely to keep working when you ignore it for
a couple of years while your daughter learns to walk and talk, say. This is kind of in opposition
to my instinct to be "clever" and use resources wisely, and certainly produces systems that
are less-efficient in many senses (but more likely to continue to work!).

As a concrete example,
consider my Synology NAS. It makes perfect sense to use the NAS to provide NAS-ish services: remote storage, file sharing in all kinds of protocols, and adjacent services like backups. Synology takes Surveillance Station (security
camera NVR) seriously and charges real money for it, so it is safe to rely on. It also makes sense
to have it co-located with bulk storage. However, think hard about peripheral (but
first-party-supported) services like "hey it can be a Primary Domain Controller for a Windows domain!"
(I've done this and now regret it.) It's true but it is very likely to tempt you into unsupported
customizations (any time you ssh into the NAS to edit some config file that isn't exposed in the UI,
the risk grows that your setup will break with the next update or the next hardware refresh);
I would generally advise against using a NAS to be a PDC, or provide single-sign-on for unrelated
services. I might use it to fill a gap in my router, if it had a better DHCP or DNS server or something,
but only for straightforward use cases that in principle could be hosted elsewhere.
What I **wouldn't** do (next time) is to look at the unused CPU and RAM on the NAS, and decide to
try to use it for general-purpose service hosting. (This became much easier to swallow once
I found some benchmarks suggesting that the Intel Xeon D-1527 @ a TDP of 35W in the RackStation, which sounds
very fancy, has almost exactly [the same performance](https://www.cpubenchmark.net/compare/3784vs6304/Intel-Xeon-D-1527-vs-Intel-N150), both single-threaded and aggregate, as a modern
Intel N150 ultra-low-power 6W chip which actually has a good deal more cache).

So in a roundabout way this explains my enterprise here: in order to stay on a brightly-lit
path, but also manage my configuration in a way that I can track over time and recreate from
notes, my answer is to adopt a full Gitops setup much more like a business than a home
computer. (The "homelab" idea in general goes this way, e.g. servethehome and folks; this is
just my personal attempt at it.)

* Heavy adoption of Terraform for both cloud and local resources, so I can avoid most pointy-clicky
  setup management. Even better, I can often set something up once in the UI (using the wizards and generally
  living the home-user "just click around" life)), then translate it into a
  Terraform config that I can then maintain in a managed way.
* Kubernetes as a primary way to allocate compute resources and manage tasks. This is more
  efficient than running VMs, more easily scaled than running Docker on multiple machines,
  but primarily opens the door to a whole world of configuration management. Once you
  have a k8s cluster available, running an incremental task on it is very easy, in contrast
  with trying to abuse the NAS as a compute server, where each incremental task made the
  whole edifice more shaky.
* Helm and ArgoCD as the primary Kubernetes configuration management tools. Helm provides a
  way to describe bundles of resources as a cohesive whole, and ArgoCD provides a way to
  synchronize that bundle into the cluster and maintain visibility into its state and any
  drift.

## What

This repo manages three-to-four chunks of config:

* `tf/bootstrap` contains Terraform that needs to be run with elevated privileges.
  It mostly exists to create and grant privileges to service accounts, to set up up the Github
  repo, and similar meta-tasks. The goal is to minimize the size of this bundle while
  providing close to the minimum necessary set of privileges to the payload bundle.
* `tf/nodes` contains Terraform configuration for provisioning two Talos Kubernetes clusters on
  an externally-created Proxmox cluster. `tiles-test` is a single worker and VM on one machine, to
  provide a testbed for both Terraform and Kubernetes config before deploying it to the "real" system.
  `tiles` is the main cluster, spread across three machines, with each machine having a smallish control
  plane and a worker VM with the bulk of the memory and cores.
  Note that the deployments are side-by-side, controlled by the config within the same repo at the same
  commit, rather than managed as separate branches or anything.
* `charts` contains Kubernetes configuration, bootstrapping to an ArgoCD setup which then deploys the
  rest of the system. Environment-specific or simply runtime onfig values are passed in from Terraform
  outputs.

## Primary Purposes

Reasons for the cluster existing at all, I mean; I'm not counting internal things like "collect its
own logs and metrics" or "provide DNS for the services it provides", rather the point of those services:

* Let's Encrypt certs for various external servers, for example my Unifi and Synology gear.
* An LGTM (Loki / Grafana / Tempo / Mimir) stack for logs and metrics collection and alerting.
  Receive or scrape metrics from
  * Synology RackStation (node_exporter running under Docker)
  * Unifi (via <https://unpoller.com/docs/poller/examples>)
  * HomeAssistant - will take some fiddling, I kind of want to export everything! Definitely
    want to support things like "raise an alert if the basement lights are on all night".
* An Apprise instance for sending centralized notifications from any systems that need to
* MQTT "broker" or whatever they call the central node, for various RaspberryPi and similar projects
  to send messages in a standard way. In particular, this could be federated from an on-device
  broker for robotic applications, so the robot could internally distribute e.g. location and
  sensor data, but also (when the network is available) bridge it back to a central node where
  we can log and archive it
* Eventually: adopt the currently-dedicated box which serves RTK GPS corrections from a fixed antenna
  in the attic over the NTRIP protocol. (This allows real-time differential GPS for robots within
  wifi reach of the house, without any additional radios or support; with a cell phone and VPN
  bridge this extends across the whole property and neighborhood.)
* QGIS or similar storage for maps and geo datasets. I have ideas about trying to keep spatial data
  from many sources and at many levels of both accuracy and density - for example, relative positions
  from a total station (sparse, very precise relatively), GPS traces from all kinds of devices
  (denser, with wildly varying precision both claimed and achieved), and lidar scans (very dense!)
  ideally all able to co-exist.

## Basic Operations: Initialization

From a cold start, with a proxmox cluster,

* Push to main, or run `nodes-plan-apply` on `tags/test` with a target of `test`,
  to trigger a deployment of the`tiles-test` cluster
* Run `bootstrap-cluster` with a target of `tiles-test` to install CRDs and initial versions of argocd, cilium and onepassword.

From there, ArgoCD will replace itself, cilium and 1password with managed versions (mostly just adding an annotation),
as well as installing the rest of the helper and payload components.

## Intended Concept of Operations: Cluster Maintenance and Deployment

These are not all worked out in detail, but the basic reasoning for this setup:

* Use `tiles-test` to get things working nicely, then apply the changes to the full cluster.
* Optionally, take down the `tiles-test` VMs when things are working, and provision another
  worker for `tiles` on that machine until needed.
* We should be able to update and reboot each Proxmox physical server, one at a time;
* We should also be able to update each control plane and worker (to new kubernetes versions
  as well as new Talos versions), again one at a time.
* As an alternative, since the Proxmox hosts are a cluster, we can migrate VMs between machines.
  So we could down the workers and make room for multiple control planes on a single machime, for
  example.
* Or we could take the node VMs out of service one-by-one and replace them instead of bothering
  to try to upgrade them
