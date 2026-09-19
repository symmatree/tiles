package main

import (
	"context"
	"fmt"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/google/go-containerregistry/pkg/name"
	"github.com/google/go-containerregistry/pkg/registry"
	"github.com/google/go-containerregistry/pkg/v1/random"
	"github.com/google/go-containerregistry/pkg/v1/remote"
)

// testRegistry serves an in-memory registry and returns its host. httptest binds
// 127.0.0.1; addressing it as localhost is what makes the client talk plain HTTP
// to it, so the test needs no insecure option in the client itself.
func testRegistry(t *testing.T) string {
	t.Helper()
	srv := httptest.NewServer(registry.New())
	t.Cleanup(srv.Close)
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("parsing server url: %v", err)
	}
	return strings.Replace(u.Host, "127.0.0.1", "localhost", 1)
}

// The digest we report has to be the one the registry stores for the tag, since
// that is what a runtime records as the pod's imageID.
func TestDigestMatchesWhatThePushedImageHas(t *testing.T) {
	host := testRegistry(t)
	image := fmt.Sprintf("%s/team/app:main", host)

	img, err := random.Image(1024, 2)
	if err != nil {
		t.Fatalf("building test image: %v", err)
	}
	ref, err := name.NewTag(image)
	if err != nil {
		t.Fatalf("parsing tag: %v", err)
	}
	if err := remote.Write(ref, img); err != nil {
		t.Fatalf("pushing test image: %v", err)
	}
	want, err := img.Digest()
	if err != nil {
		t.Fatalf("digesting test image: %v", err)
	}

	got, err := newRegistryClient().Digest(context.Background(), image)
	if err != nil {
		t.Fatalf("Digest: %v", err)
	}
	if got != want.String() {
		t.Fatalf("Digest = %q, want %q", got, want.String())
	}
}

func TestDigestReportsAMissingTag(t *testing.T) {
	host := testRegistry(t)
	if _, err := newRegistryClient().Digest(context.Background(), host+"/team/app:nope"); err == nil {
		t.Fatal("want an error for a tag the registry does not have")
	}
}

func TestDigestReportsAnUnparseableReference(t *testing.T) {
	if _, err := newRegistryClient().Digest(context.Background(), "NOT A REF"); err == nil {
		t.Fatal("want an error for a reference that does not parse")
	}
}
