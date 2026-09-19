package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))

	cfg := Config{
		RepoURL:    getenv("REPO_URL", "https://github.com/symmatree/tiles.git"),
		Ref:        getenv("WATCH_REF", "prod"),
		Interval:   getenvDuration("INTERVAL", 60*time.Second),
		BatchSize:  getenvInt("BATCH_SIZE", 4),
		BatchDelay: getenvDuration("BATCH_DELAY", 5*time.Second),
	}
	ns := getenv("ARGOCD_NAMESPACE", "argocd")

	refresher, err := newK8sRefresher(ns)
	if err != nil {
		log.Error("failed to build kubernetes client", "err", err)
		os.Exit(1)
	}

	roller, err := newK8sRoller()
	if err != nil {
		log.Error("failed to build kubernetes client", "err", err)
		os.Exit(1)
	}
	imageInterval := getenvDuration("IMAGE_INTERVAL", 5*time.Minute)

	gitWatcher := New(cfg, gitLsRemote{}, refresher, log)
	imageWatcher := NewImageWatcher(imageInterval, roller, newRegistryClient(), log)
	log.Info("starting argo-tag-watcher",
		"repo", cfg.RepoURL, "ref", cfg.Ref, "namespace", ns,
		"interval", cfg.Interval, "batchSize", cfg.BatchSize, "batchDelay", cfg.BatchDelay,
		"imageInterval", imageInterval, "rollAnnotation", RollAnnotation)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Two independent watchers in one process: both notice a ref has moved and poke
	// the thing that has not caught up. They share nothing but the process.
	var wg sync.WaitGroup
	var failed atomic.Bool
	for name, run := range map[string]func(context.Context) error{
		"git":   gitWatcher.Run,
		"image": imageWatcher.Run,
	} {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := run(ctx); err != nil && ctx.Err() == nil {
				log.Error("watcher exited with error", "watcher", name, "err", err)
				failed.Store(true)
				stop() // one watcher dying takes the pod down, rather than half-working
			}
		}()
	}
	wg.Wait()
	if failed.Load() {
		os.Exit(1)
	}
}

// gitLsRemote resolves a ref via `git ls-remote`, preferring the peeled commit of
// an annotated tag (the `^{}` entry) so a force-moved annotated tag reports the
// commit it points at, not the tag object.
type gitLsRemote struct{}

func (gitLsRemote) Resolve(ctx context.Context, repoURL, ref string) (string, error) {
	out, err := exec.CommandContext(ctx, "git", "ls-remote", repoURL, ref, ref+"^{}").Output()
	if err != nil {
		return "", fmt.Errorf("git ls-remote %s %s: %w", repoURL, ref, err)
	}
	sha := parseLsRemote(string(out), ref)
	if sha == "" {
		return "", fmt.Errorf("ref %q not found in %s", ref, repoURL)
	}
	return sha, nil
}

// parseLsRemote picks the SHA for ref from `git ls-remote` output. If both the ref
// and its peeled form (refs/tags/<ref>^{}) are present -- an annotated tag -- the
// peeled commit wins. Pure and offline so it can be unit-tested.
func parseLsRemote(out, ref string) string {
	var plain string
	suffixes := []string{"refs/tags/" + ref, "refs/heads/" + ref, ref}
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		sha, name := fields[0], fields[1]
		for _, s := range suffixes {
			if name == s+"^{}" {
				return sha // peeled annotated tag -> commit; highest priority
			}
			if name == s && plain == "" {
				plain = sha
			}
		}
	}
	return plain
}

// argo Application CRD coordinates.
var appGVR = schema.GroupVersionResource{Group: "argoproj.io", Version: "v1alpha1", Resource: "applications"}

type k8sRefresher struct {
	dyn dynamic.Interface
	ns  string
}

func newK8sRefresher(ns string) (*k8sRefresher, error) {
	restCfg, err := rest.InClusterConfig()
	if err != nil {
		return nil, err
	}
	dyn, err := dynamic.NewForConfig(restCfg)
	if err != nil {
		return nil, err
	}
	return &k8sRefresher{dyn: dyn, ns: ns}, nil
}

func (k *k8sRefresher) ListApps(ctx context.Context) ([]string, error) {
	list, err := k.dyn.Resource(appGVR).Namespace(k.ns).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(list.Items))
	for _, item := range list.Items {
		names = append(names, item.GetName())
	}
	return names, nil
}

// Refresh sets the refresh annotation; the application-controller picks it up and
// clears it after refreshing. A merge patch is idempotent and never fights the
// controller over other fields.
func (k *k8sRefresher) Refresh(ctx context.Context, name string) error {
	patch := []byte(`{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}`)
	_, err := k.dyn.Resource(appGVR).Namespace(k.ns).Patch(ctx, name, types.MergePatchType, patch, metav1.PatchOptions{})
	return err
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func getenvDuration(key string, def time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return def
}

func getenvInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil {
			return n
		}
	}
	return def
}
