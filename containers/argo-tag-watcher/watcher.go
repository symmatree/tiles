// Command argo-tag-watcher polls a git ref (the moving prod/test tag) and, when
// its commit SHA changes, asks Argo CD to refresh every Application by setting the
// argocd.argoproj.io/refresh annotation. It exists because Argo's periodic resync
// can quietly stop re-enqueuing apps, leaving them Synced/Healthy but pinned to a
// stale revision until something pokes them (symmatree/tiles#667). This is the
// external poke.
//
// It deliberately does no filtering: on a tag move it refreshes ALL apps. A
// refresh of an app that did not change is a cheap no-op that just re-checks and
// updates reconciledAt, so there is nothing to gain by trying to guess which apps
// "need" it -- and nothing to miss.
package main

import (
	"context"
	"log/slog"
	"time"
)

// TagResolver resolves a git ref (branch or tag) to a commit SHA.
type TagResolver interface {
	Resolve(ctx context.Context, repoURL, ref string) (string, error)
}

// AppRefresher lists Argo CD Applications and requests a refresh of one by name.
type AppRefresher interface {
	ListApps(ctx context.Context) ([]string, error)
	Refresh(ctx context.Context, name string) error
}

// Config is the watcher's runtime configuration.
type Config struct {
	RepoURL    string        // git repo to poll
	Ref        string        // ref to watch, e.g. "prod"
	Interval   time.Duration // poll period
	BatchSize  int           // apps refreshed per batch (<=0 means all at once)
	BatchDelay time.Duration // pause between batches, to stay gentle on the repo-server
}

// Watcher polls a ref and refreshes all apps when its SHA changes.
type Watcher struct {
	cfg       Config
	resolver  TagResolver
	refresher AppRefresher
	log       *slog.Logger

	lastSHA string // last SHA we successfully converged on ("" until first success)
}

// New constructs a Watcher.
func New(cfg Config, resolver TagResolver, refresher AppRefresher, log *slog.Logger) *Watcher {
	if log == nil {
		log = slog.Default()
	}
	return &Watcher{cfg: cfg, resolver: resolver, refresher: refresher, log: log}
}

// Run polls until ctx is cancelled. It checks once immediately (so a fresh start
// converges any drift accumulated while it was down) and then every Interval.
func (w *Watcher) Run(ctx context.Context) error {
	w.tick(ctx)
	t := time.NewTicker(w.cfg.Interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-t.C:
			w.tick(ctx)
		}
	}
}

func (w *Watcher) tick(ctx context.Context) {
	if _, err := w.checkOnce(ctx); err != nil {
		w.log.Error("check failed", "ref", w.cfg.Ref, "err", err)
	}
}

// checkOnce resolves the ref and, if the SHA differs from the last one we
// converged on, refreshes every app. It advances lastSHA only after a successful
// refresh pass, so a transient git/list error just means we retry next tick
// (re-refreshing is harmless). The first observation (lastSHA == "") always counts
// as a change, which is what converges apps on startup.
//
// Returns true if a refresh was triggered.
func (w *Watcher) checkOnce(ctx context.Context) (bool, error) {
	sha, err := w.resolver.Resolve(ctx, w.cfg.RepoURL, w.cfg.Ref)
	if err != nil {
		return false, err
	}
	if sha == w.lastSHA {
		return false, nil
	}

	apps, err := w.refresher.ListApps(ctx)
	if err != nil {
		return false, err
	}
	w.log.Info("ref changed; refreshing all apps",
		"ref", w.cfg.Ref, "from", orNone(w.lastSHA), "to", sha, "apps", len(apps))
	if err := w.refreshBatched(ctx, apps); err != nil {
		return false, err
	}
	w.lastSHA = sha
	return true, nil
}

// refreshBatched refreshes apps in batches of BatchSize, pausing BatchDelay
// between batches. A single app's refresh failure is logged and skipped rather
// than aborting the pass. It returns an error only if ctx is cancelled.
func (w *Watcher) refreshBatched(ctx context.Context, apps []string) error {
	for i, batch := range batchesOf(apps, w.cfg.BatchSize) {
		if i > 0 && w.cfg.BatchDelay > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(w.cfg.BatchDelay):
			}
		}
		for _, app := range batch {
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := w.refresher.Refresh(ctx, app); err != nil {
				w.log.Warn("refresh failed", "app", app, "err", err)
			}
		}
	}
	return nil
}

// batchesOf splits items into slices of at most size (size <= 0 means one batch).
func batchesOf[T any](items []T, size int) [][]T {
	if size <= 0 || size >= len(items) {
		if len(items) == 0 {
			return nil
		}
		return [][]T{items}
	}
	var out [][]T
	for i := 0; i < len(items); i += size {
		end := i + size
		if end > len(items) {
			end = len(items)
		}
		out = append(out, items[i:end])
	}
	return out
}

func orNone(s string) string {
	if s == "" {
		return "(startup)"
	}
	return s
}
