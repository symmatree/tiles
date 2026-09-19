package main

import (
	"context"
	"log/slog"
	"strings"
	"time"
)

// RollAnnotation opts a workload in. The watcher then compares every container
// image in its pod template against the registry, so the workload names nothing:
// the images it runs are already in its spec, and a second copy in an annotation
// is one that can drift from it.
const RollAnnotation = "tiles.symmatree.com/roll-on-digest-change"

// Workload is the kind-agnostic view of an opted-in Deployment, StatefulSet or
// DaemonSet.
type Workload struct {
	Kind      string
	Namespace string
	Name      string
	// Selector is the pod selector as a label-selector string.
	Selector string
	// Containers maps container name to the image reference in the pod template.
	Containers map[string]string
	// Settled is false while a rollout is in flight (the controller has not yet
	// observed the current generation, or old pods are still around). Digests are
	// only comparable once it is true: mid-rollout, pods of both revisions match
	// the selector, so the old ones would look like a reason to restart again.
	Settled bool
}

func (w Workload) ref() string { return w.Kind + " " + w.Namespace + "/" + w.Name }

// Pod is a running pod's view of what it actually pulled.
type Pod struct {
	Name string
	// ImageIDs maps container name to the digest the runtime recorded, e.g.
	// "sha256:abc..." extracted from `ghcr.io/x/y@sha256:abc...`.
	ImageIDs map[string]string
}

// Roller lists opted-in workloads and their pods, and restarts one.
type Roller interface {
	ListWorkloads(ctx context.Context) ([]Workload, error)
	ListPods(ctx context.Context, namespace, selector string) ([]Pod, error)
	Restart(ctx context.Context, w Workload) error
}

// ImageWatcher rolls opted-in workloads whose floating image tag has moved.
//
// Stateless by comparison: the registry digest for the tag versus the digest the
// pod actually pulled. They differ, we restart; the new pod re-pulls and they
// match, so nothing keeps firing and there is no last-seen state to store or lose.
// This requires imagePullPolicy: Always on the workload -- without it the new pod
// reuses the cached image and the mismatch never clears.
type ImageWatcher struct {
	interval time.Duration
	roller   Roller
	registry DigestResolver
	log      *slog.Logger
}

// NewImageWatcher constructs an ImageWatcher.
func NewImageWatcher(interval time.Duration, roller Roller, registry DigestResolver, log *slog.Logger) *ImageWatcher {
	if log == nil {
		log = slog.Default()
	}
	return &ImageWatcher{interval: interval, roller: roller, registry: registry, log: log}
}

// Run checks every interval until ctx is cancelled, starting immediately so a
// restart of the watcher converges whatever moved while it was down.
func (w *ImageWatcher) Run(ctx context.Context) error {
	if _, err := w.checkOnce(ctx); err != nil {
		w.log.Error("image check failed", "err", err)
	}
	t := time.NewTicker(w.interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-t.C:
			if _, err := w.checkOnce(ctx); err != nil {
				w.log.Error("image check failed", "err", err)
			}
		}
	}
}

// checkOnce restarts every opted-in workload running a digest the registry has
// moved off. One workload's failure does not stop the pass; only listing the
// workloads at all is fatal to it. Returns the number of workloads restarted.
func (w *ImageWatcher) checkOnce(ctx context.Context) (int, error) {
	workloads, err := w.roller.ListWorkloads(ctx)
	if err != nil {
		return 0, err
	}
	restarted := 0
	for _, wl := range workloads {
		if err := ctx.Err(); err != nil {
			return restarted, err
		}
		if !wl.Settled {
			w.log.Info("rollout in flight; leaving it alone", "workload", wl.ref())
			continue
		}
		stale, err := w.staleImages(ctx, wl)
		if err != nil {
			w.log.Warn("could not compare digests", "workload", wl.ref(), "err", err)
			continue
		}
		if len(stale) == 0 {
			continue
		}
		w.log.Info("image digest moved; restarting", "workload", wl.ref(), "images", stale)
		if err := w.roller.Restart(ctx, wl); err != nil {
			w.log.Warn("restart failed", "workload", wl.ref(), "err", err)
			continue
		}
		restarted++
	}
	return restarted, nil
}

// staleImages returns the image references whose registry digest differs from
// what some pod of the workload is running. A container nothing reports a digest
// for is not evidence of staleness and is skipped.
func (w *ImageWatcher) staleImages(ctx context.Context, wl Workload) ([]string, error) {
	pods, err := w.roller.ListPods(ctx, wl.Namespace, wl.Selector)
	if err != nil {
		return nil, err
	}
	if len(pods) == 0 {
		return nil, nil
	}
	var stale []string
	for name, image := range wl.Containers {
		running := runningDigests(pods, name)
		if len(running) == 0 {
			continue
		}
		if strings.Contains(image, "@") {
			// Digest-pinned: the tag cannot move out from under it.
			continue
		}
		want, err := w.registry.Digest(ctx, image)
		if err != nil {
			w.log.Warn("registry lookup failed", "workload", wl.ref(), "image", image, "err", err)
			continue
		}
		for _, have := range running {
			if have != want {
				stale = append(stale, image)
				break
			}
		}
	}
	return stale, nil
}

// runningDigests collects the digests the pods report for one container.
func runningDigests(pods []Pod, container string) []string {
	var out []string
	for _, p := range pods {
		if d := p.ImageIDs[container]; d != "" {
			out = append(out, d)
		}
	}
	return out
}

// digestFromImageID pulls the digest out of a container status imageID. CRI
// runtimes report `repo@sha256:...`; anything else (a bare config ID, as some
// runtimes report) is not a manifest digest and is not comparable, so it yields
// "" and the container is skipped rather than restarted on a false mismatch.
func digestFromImageID(imageID string) string {
	_, digest, ok := strings.Cut(imageID, "@")
	if !ok || !strings.HasPrefix(digest, "sha256:") {
		return ""
	}
	return digest
}
