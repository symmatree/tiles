package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestParseImageRef(t *testing.T) {
	cases := []struct {
		image           string
		host, repo, tag string
		wantErr         bool
	}{
		{image: "ghcr.io/symmatree/tiles/mavproxy:main",
			host: "ghcr.io", repo: "symmatree/tiles/mavproxy", tag: "main"},
		{image: "ghcr.io/symmatree/coordinator-fleet-control:main",
			host: "ghcr.io", repo: "symmatree/coordinator-fleet-control", tag: "main"},
		// No tag means latest.
		{image: "ghcr.io/symmatree/tiles/rtkbase",
			host: "ghcr.io", repo: "symmatree/tiles/rtkbase", tag: "latest"},
		// A colon before the last slash is a registry port, not a tag.
		{image: "registry.local:5000/team/app:v2",
			host: "registry.local:5000", repo: "team/app", tag: "v2"},
		{image: "localhost:5000/app:v2",
			host: "localhost:5000", repo: "app", tag: "v2"},
		// Docker Hub: bare names are official images, and the API host differs
		// from the name in the reference.
		{image: "nginx:1.27", host: "registry-1.docker.io", repo: "library/nginx", tag: "1.27"},
		{image: "grafana/grafana:11.0.0", host: "registry-1.docker.io", repo: "grafana/grafana", tag: "11.0.0"},
		{image: "docker.io/grafana/grafana:11.0.0", host: "registry-1.docker.io", repo: "grafana/grafana", tag: "11.0.0"},
		// Already pinned: nothing to resolve.
		{image: "ghcr.io/x/y@sha256:abc", wantErr: true},
	}
	for _, c := range cases {
		host, repo, tag, err := parseImageRef(c.image)
		if c.wantErr {
			if err == nil {
				t.Errorf("parseImageRef(%q): want error", c.image)
			}
			continue
		}
		if err != nil {
			t.Errorf("parseImageRef(%q): %v", c.image, err)
			continue
		}
		if host != c.host || repo != c.repo || tag != c.tag {
			t.Errorf("parseImageRef(%q) = %q %q %q, want %q %q %q",
				c.image, host, repo, tag, c.host, c.repo, c.tag)
		}
	}
}

func TestParseChallenge(t *testing.T) {
	got := parseChallenge(`Bearer realm="https://ghcr.io/token",service="ghcr.io",scope="repository:symmatree/tiles/mavproxy:pull,push"`)
	want := map[string]string{
		"realm":   "https://ghcr.io/token",
		"service": "ghcr.io",
		// The comma inside the quoted scope must not split it.
		"scope": "repository:symmatree/tiles/mavproxy:pull,push",
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("challenge[%q] = %q, want %q", k, got[k], v)
		}
	}
}

// fakeRegistryServer serves one manifest for one tag behind a Bearer challenge,
// the way GHCR does.
func fakeRegistryServer(t *testing.T, manifest string) *httptest.Server {
	t.Helper()
	const token = "a-token"
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/token":
			if r.URL.Query().Get("scope") != "repository:team/app:pull" {
				t.Errorf("token scope = %q", r.URL.Query().Get("scope"))
			}
			fmt.Fprintf(w, `{"token":%q}`, token)
		case r.URL.Path == "/v2/team/app/manifests/main":
			if r.Header.Get("Authorization") != "Bearer "+token {
				w.Header().Set("WWW-Authenticate",
					fmt.Sprintf(`Bearer realm="%s/token",service="registry",scope="repository:team/app:pull"`, srv.URL))
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			if !strings.Contains(r.Header.Get("Accept"), "application/vnd.oci.image.index.v1+json") {
				t.Errorf("Accept header did not offer an index: %q", r.Header.Get("Accept"))
			}
			w.Header().Set("Content-Type", "application/vnd.docker.distribution.manifest.v2+json")
			fmt.Fprint(w, manifest)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

// The digest of a manifest is the sha256 of its bytes, which is what containerd
// records as the pod's imageID -- so we compute it rather than trusting a header.
func TestDigestAnswersBearerChallengeAndHashesTheBody(t *testing.T) {
	const manifest = `{"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json"}`
	srv := fakeRegistryServer(t, manifest)

	c := &registryClient{http: srv.Client(), scheme: "http"}
	host := strings.TrimPrefix(srv.URL, "http://")
	got, err := c.Digest(context.Background(), host+"/team/app:main")
	if err != nil {
		t.Fatalf("Digest: %v", err)
	}
	sum := sha256.Sum256([]byte(manifest))
	want := "sha256:" + hex.EncodeToString(sum[:])
	if got != want {
		t.Fatalf("Digest = %q, want %q", got, want)
	}
}

func TestDigestReportsMissingTag(t *testing.T) {
	srv := fakeRegistryServer(t, "{}")
	c := &registryClient{http: srv.Client(), scheme: "http"}
	host := strings.TrimPrefix(srv.URL, "http://")
	if _, err := c.Digest(context.Background(), host+"/team/app:nope"); err == nil {
		t.Fatal("want an error for a tag the registry does not have")
	}
}
