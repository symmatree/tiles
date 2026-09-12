package main

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"reflect"
	"sync"
	"testing"
	"time"
)

func quietLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

// fakeResolver returns scripted SHAs (or an error) per call.
type fakeResolver struct {
	shas []string
	err  error
	n    int
}

func (f *fakeResolver) Resolve(_ context.Context, _, _ string) (string, error) {
	if f.err != nil {
		return "", f.err
	}
	sha := f.shas[min(f.n, len(f.shas)-1)]
	f.n++
	return sha, nil
}

// fakeRefresher records which apps were refreshed.
type fakeRefresher struct {
	mu        sync.Mutex
	apps      []string
	listErr   error
	failApps  map[string]bool // apps whose Refresh returns an error
	refreshed []string
}

func (f *fakeRefresher) ListApps(context.Context) ([]string, error) {
	if f.listErr != nil {
		return nil, f.listErr
	}
	return f.apps, nil
}

func (f *fakeRefresher) Refresh(_ context.Context, name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.refreshed = append(f.refreshed, name)
	if f.failApps[name] {
		return errors.New("boom")
	}
	return nil
}

func testConfig() Config {
	return Config{RepoURL: "r", Ref: "prod", Interval: time.Hour, BatchSize: 2, BatchDelay: 0}
}

func TestCheckOnce_FirstObservationRefreshesAll(t *testing.T) {
	res := &fakeResolver{shas: []string{"sha-a"}}
	ref := &fakeRefresher{apps: []string{"one", "two", "three"}}
	w := New(testConfig(), res, ref, quietLogger())

	triggered, err := w.checkOnce(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !triggered {
		t.Fatal("expected first observation to trigger a refresh")
	}
	if !reflect.DeepEqual(ref.refreshed, []string{"one", "two", "three"}) {
		t.Fatalf("expected all apps refreshed, got %v", ref.refreshed)
	}
}

func TestCheckOnce_UnchangedShaDoesNothing(t *testing.T) {
	res := &fakeResolver{shas: []string{"sha-a", "sha-a"}}
	ref := &fakeRefresher{apps: []string{"one", "two"}}
	w := New(testConfig(), res, ref, quietLogger())

	if _, err := w.checkOnce(context.Background()); err != nil {
		t.Fatalf("first check: %v", err)
	}
	before := len(ref.refreshed)

	triggered, err := w.checkOnce(context.Background())
	if err != nil {
		t.Fatalf("second check: %v", err)
	}
	if triggered {
		t.Fatal("expected no refresh when SHA is unchanged")
	}
	if len(ref.refreshed) != before {
		t.Fatalf("expected no new refreshes, got %v", ref.refreshed[before:])
	}
}

func TestCheckOnce_ChangedShaRefreshesAgain(t *testing.T) {
	res := &fakeResolver{shas: []string{"sha-a", "sha-b"}}
	ref := &fakeRefresher{apps: []string{"one"}}
	w := New(testConfig(), res, ref, quietLogger())

	if _, _ = w.checkOnce(context.Background()); len(ref.refreshed) != 1 {
		t.Fatalf("first check refreshed %v", ref.refreshed)
	}
	triggered, err := w.checkOnce(context.Background())
	if err != nil {
		t.Fatalf("second check: %v", err)
	}
	if !triggered || len(ref.refreshed) != 2 {
		t.Fatalf("expected a second refresh on SHA change, got triggered=%v refreshed=%v", triggered, ref.refreshed)
	}
}

func TestCheckOnce_ResolveErrorDoesNotAdvance(t *testing.T) {
	res := &fakeResolver{err: errors.New("network down")}
	ref := &fakeRefresher{apps: []string{"one"}}
	w := New(testConfig(), res, ref, quietLogger())

	if _, err := w.checkOnce(context.Background()); err == nil {
		t.Fatal("expected error from resolve")
	}
	if len(ref.refreshed) != 0 {
		t.Fatalf("expected no refreshes on resolve error, got %v", ref.refreshed)
	}
	// After the resolver recovers, the change should still be detected (lastSHA
	// was not advanced by the failed attempt).
	res.err = nil
	res.shas = []string{"sha-a"}
	triggered, err := w.checkOnce(context.Background())
	if err != nil || !triggered {
		t.Fatalf("expected recovery to trigger a refresh, got triggered=%v err=%v", triggered, err)
	}
}

func TestCheckOnce_ListErrorDoesNotAdvance(t *testing.T) {
	res := &fakeResolver{shas: []string{"sha-a", "sha-a"}}
	ref := &fakeRefresher{apps: []string{"one"}, listErr: errors.New("api down")}
	w := New(testConfig(), res, ref, quietLogger())

	if _, err := w.checkOnce(context.Background()); err == nil {
		t.Fatal("expected list error")
	}
	// lastSHA must not have advanced, so a subsequent successful list still fires.
	ref.listErr = nil
	triggered, err := w.checkOnce(context.Background())
	if err != nil || !triggered {
		t.Fatalf("expected refresh after list recovers, got triggered=%v err=%v", triggered, err)
	}
}

func TestRefreshBatched_PerAppErrorIsSkipped(t *testing.T) {
	res := &fakeResolver{shas: []string{"sha-a"}}
	ref := &fakeRefresher{apps: []string{"one", "two", "three"}, failApps: map[string]bool{"two": true}}
	w := New(testConfig(), res, ref, quietLogger())

	triggered, err := w.checkOnce(context.Background())
	if err != nil || !triggered {
		t.Fatalf("expected trigger despite one app failing, got triggered=%v err=%v", triggered, err)
	}
	// All three attempted even though "two" failed, and lastSHA advanced.
	if !reflect.DeepEqual(ref.refreshed, []string{"one", "two", "three"}) {
		t.Fatalf("expected all apps attempted, got %v", ref.refreshed)
	}
	if again, _ := w.checkOnce(context.Background()); again {
		t.Fatal("expected lastSHA to have advanced (no re-trigger on same SHA)")
	}
}

func TestBatchesOf(t *testing.T) {
	cases := []struct {
		items []int
		size  int
		want  [][]int
	}{
		{[]int{1, 2, 3, 4, 5, 6, 7}, 3, [][]int{{1, 2, 3}, {4, 5, 6}, {7}}},
		{[]int{1, 2}, 5, [][]int{{1, 2}}},
		{[]int{1, 2, 3}, 0, [][]int{{1, 2, 3}}},
		{[]int{}, 3, nil},
		{[]int{1, 2, 3, 4}, 2, [][]int{{1, 2}, {3, 4}}},
	}
	for _, c := range cases {
		got := batchesOf(c.items, c.size)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("batchesOf(%v,%d)=%v want %v", c.items, c.size, got, c.want)
		}
	}
}

func TestParseLsRemote(t *testing.T) {
	annotated := "" +
		"03c96041e811234037b6821957aeddc4c56b56f4\trefs/tags/prod\n" +
		"b0b50f71a651a8593f48f70bda9800565d0c79ec\trefs/tags/prod^{}\n"
	lightweight := "f1c1934ce11a0e0e8a767911b8fc4847bbe2c6ea\trefs/tags/test\n"
	branch := "aaaa111122223333444455556666777788889999\trefs/heads/prod\n"

	cases := []struct {
		name, out, ref, want string
	}{
		{"annotated tag peels to commit", annotated, "prod", "b0b50f71a651a8593f48f70bda9800565d0c79ec"},
		{"lightweight tag", lightweight, "test", "f1c1934ce11a0e0e8a767911b8fc4847bbe2c6ea"},
		{"branch", branch, "prod", "aaaa111122223333444455556666777788889999"},
		{"missing ref", lightweight, "prod", ""},
	}
	for _, c := range cases {
		if got := parseLsRemote(c.out, c.ref); got != c.want {
			t.Errorf("%s: parseLsRemote(ref=%q)=%q want %q", c.name, c.ref, got, c.want)
		}
	}
}
