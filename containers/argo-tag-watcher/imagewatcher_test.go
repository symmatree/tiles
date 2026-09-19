package main

import (
	"context"
	"errors"
	"testing"
	"time"
)

// fakeRoller serves scripted workloads and pods and records restarts.
type fakeRoller struct {
	workloads  []Workload
	pods       map[string][]Pod // namespace/selector -> pods
	listErr    error
	restartErr error
	restarted  []string
}

func (f *fakeRoller) ListWorkloads(context.Context) ([]Workload, error) {
	if f.listErr != nil {
		return nil, f.listErr
	}
	return f.workloads, nil
}

func (f *fakeRoller) ListPods(_ context.Context, ns, selector string) ([]Pod, error) {
	return f.pods[ns+"/"+selector], nil
}

func (f *fakeRoller) Restart(_ context.Context, w Workload) error {
	f.restarted = append(f.restarted, w.ref())
	return f.restartErr
}

// fakeRegistry answers with a scripted digest per image.
type fakeRegistry struct {
	digests map[string]string
	err     error
	calls   int
}

func (f *fakeRegistry) Digest(_ context.Context, image string) (string, error) {
	f.calls++
	if f.err != nil {
		return "", f.err
	}
	d, ok := f.digests[image]
	if !ok {
		return "", errors.New("no such image")
	}
	return d, nil
}

const (
	oldDigest = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
	newDigest = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
)

// settledWorkload is one opted-in Deployment running image `img` in container "app".
func settledWorkload(img string) Workload {
	return Workload{
		Kind: "Deployment", Namespace: "ns", Name: "app",
		Selector:   "app=x",
		Containers: map[string]string{"app": img},
		Settled:    true,
	}
}

func newTestImageWatcher(r *fakeRoller, reg *fakeRegistry) *ImageWatcher {
	return NewImageWatcher(time.Minute, r, reg, quietLogger())
}

func TestRestartsWhenDigestMoved(t *testing.T) {
	r := &fakeRoller{
		workloads: []Workload{settledWorkload("ghcr.io/x/y:main")},
		pods:      map[string][]Pod{"ns/app=x": {{Name: "p1", ImageIDs: map[string]string{"app": oldDigest}}}},
	}
	reg := &fakeRegistry{digests: map[string]string{"ghcr.io/x/y:main": newDigest}}

	n, err := newTestImageWatcher(r, reg).checkOnce(context.Background())
	if err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	if n != 1 || len(r.restarted) != 1 {
		t.Fatalf("want 1 restart, got n=%d restarted=%v", n, r.restarted)
	}
}

func TestNoRestartWhenDigestMatches(t *testing.T) {
	r := &fakeRoller{
		workloads: []Workload{settledWorkload("ghcr.io/x/y:main")},
		pods:      map[string][]Pod{"ns/app=x": {{Name: "p1", ImageIDs: map[string]string{"app": newDigest}}}},
	}
	reg := &fakeRegistry{digests: map[string]string{"ghcr.io/x/y:main": newDigest}}

	if _, err := newTestImageWatcher(r, reg).checkOnce(context.Background()); err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	if len(r.restarted) != 0 {
		t.Fatalf("restarted %v, want none", r.restarted)
	}
}

// A rollout we started is still in flight, so pods of both revisions match the
// selector. Restarting again there would reset the rollout, repeatedly.
func TestUnsettledWorkloadIsLeftAlone(t *testing.T) {
	w := settledWorkload("ghcr.io/x/y:main")
	w.Settled = false
	r := &fakeRoller{
		workloads: []Workload{w},
		pods:      map[string][]Pod{"ns/app=x": {{Name: "p1", ImageIDs: map[string]string{"app": oldDigest}}}},
	}
	reg := &fakeRegistry{digests: map[string]string{"ghcr.io/x/y:main": newDigest}}

	if _, err := newTestImageWatcher(r, reg).checkOnce(context.Background()); err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	if len(r.restarted) != 0 {
		t.Fatalf("restarted %v, want none", r.restarted)
	}
	if reg.calls != 0 {
		t.Fatalf("hit the registry %d times for an unsettled workload", reg.calls)
	}
}

// Workloads without the annotation never reach the watcher; one with it but no
// running pods has nothing to compare against.
func TestNoPodsMeansNoRestart(t *testing.T) {
	r := &fakeRoller{workloads: []Workload{settledWorkload("ghcr.io/x/y:main")}}
	reg := &fakeRegistry{digests: map[string]string{"ghcr.io/x/y:main": newDigest}}

	if _, err := newTestImageWatcher(r, reg).checkOnce(context.Background()); err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	if len(r.restarted) != 0 {
		t.Fatalf("restarted %v, want none", r.restarted)
	}
}

func TestDigestPinnedImageIsSkipped(t *testing.T) {
	pinned := "ghcr.io/x/y@" + oldDigest
	r := &fakeRoller{
		workloads: []Workload{settledWorkload(pinned)},
		pods:      map[string][]Pod{"ns/app=x": {{Name: "p1", ImageIDs: map[string]string{"app": oldDigest}}}},
	}
	reg := &fakeRegistry{digests: map[string]string{}}

	if _, err := newTestImageWatcher(r, reg).checkOnce(context.Background()); err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	if reg.calls != 0 {
		t.Fatalf("looked up a digest-pinned image %d times", reg.calls)
	}
	if len(r.restarted) != 0 {
		t.Fatalf("restarted %v, want none", r.restarted)
	}
}

// A container the pod reports no digest for -- not started, or a runtime that
// reports a config ID rather than a repo digest -- is not evidence of staleness.
func TestContainerWithoutDigestIsSkipped(t *testing.T) {
	r := &fakeRoller{
		workloads: []Workload{settledWorkload("ghcr.io/x/y:main")},
		pods:      map[string][]Pod{"ns/app=x": {{Name: "p1", ImageIDs: map[string]string{}}}},
	}
	reg := &fakeRegistry{digests: map[string]string{"ghcr.io/x/y:main": newDigest}}

	if _, err := newTestImageWatcher(r, reg).checkOnce(context.Background()); err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	if len(r.restarted) != 0 {
		t.Fatalf("restarted %v, want none", r.restarted)
	}
}

// A registry that cannot be reached leaves the workload running, and does not
// stop the pass for the workloads after it.
func TestRegistryFailureDoesNotRestartOrAbort(t *testing.T) {
	second := settledWorkload("ghcr.io/x/z:main")
	second.Name = "other"
	r := &fakeRoller{
		workloads: []Workload{settledWorkload("ghcr.io/x/y:main"), second},
		pods: map[string][]Pod{
			"ns/app=x": {{Name: "p1", ImageIDs: map[string]string{"app": oldDigest}}},
		},
	}
	reg := &fakeRegistry{digests: map[string]string{"ghcr.io/x/z:main": newDigest}}

	n, err := newTestImageWatcher(r, reg).checkOnce(context.Background())
	if err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	// The first workload's lookup fails; the second is compared and rolled.
	if n != 1 || len(r.restarted) != 1 || r.restarted[0] != second.ref() {
		t.Fatalf("want only %s restarted, got n=%d restarted=%v", second.ref(), n, r.restarted)
	}
}

func TestListWorkloadsFailureIsReturned(t *testing.T) {
	r := &fakeRoller{listErr: errors.New("api down")}
	if _, err := newTestImageWatcher(r, &fakeRegistry{}).checkOnce(context.Background()); err == nil {
		t.Fatal("want an error when listing workloads fails")
	}
}

// One sidecar moving is enough; the other containers are left as they are.
func TestSidecarMovingRestartsTheWorkload(t *testing.T) {
	w := settledWorkload("ghcr.io/x/y:v1.2.3")
	w.Containers["sidecar"] = "ghcr.io/x/hook:main"
	r := &fakeRoller{
		workloads: []Workload{w},
		pods: map[string][]Pod{"ns/app=x": {{Name: "p1", ImageIDs: map[string]string{
			"app":     newDigest,
			"sidecar": oldDigest,
		}}}},
	}
	reg := &fakeRegistry{digests: map[string]string{
		"ghcr.io/x/y:v1.2.3":  newDigest,
		"ghcr.io/x/hook:main": newDigest,
	}}

	if _, err := newTestImageWatcher(r, reg).checkOnce(context.Background()); err != nil {
		t.Fatalf("checkOnce: %v", err)
	}
	if len(r.restarted) != 1 {
		t.Fatalf("restarted %v, want one", r.restarted)
	}
}

func TestDigestFromImageID(t *testing.T) {
	cases := map[string]string{
		"ghcr.io/symmatree/tiles/mavproxy@" + oldDigest: oldDigest,
		// A bare config ID is not a manifest digest, so it is not comparable.
		oldDigest:                     "",
		"":                            "",
		"ghcr.io/x/y@md5:deadbeef":    "",
		"docker.io/library/nginx:1.2": "",
	}
	for in, want := range cases {
		if got := digestFromImageID(in); got != want {
			t.Errorf("digestFromImageID(%q) = %q, want %q", in, got, want)
		}
	}
}
