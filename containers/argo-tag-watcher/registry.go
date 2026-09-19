package main

import (
	"context"
	"fmt"

	"github.com/google/go-containerregistry/pkg/authn"
	"github.com/google/go-containerregistry/pkg/name"
	"github.com/google/go-containerregistry/pkg/v1/remote"
)

// DigestResolver resolves an image reference to the digest its tag points at.
type DigestResolver interface {
	Digest(ctx context.Context, image string) (string, error)
}

// registryClient resolves tags through the registry API.
//
// The digest it returns is whatever the tag points at -- a manifest for a
// single-platform image, an index for a multi-arch build -- which is the same
// thing containerd records as the pod's imageID, so the two compare directly.
type registryClient struct {
	options []remote.Option
}

// newRegistryClient builds a client that authenticates the way any container tool
// does: from the ambient docker config if there is one, anonymously if not. The
// packages watched today are public and resolve with no credentials; a private
// registry would need a pull secret mounted and nothing here.
func newRegistryClient() *registryClient {
	return &registryClient{options: []remote.Option{
		remote.WithAuthFromKeychain(authn.DefaultKeychain),
	}}
}

func (c *registryClient) Digest(ctx context.Context, image string) (string, error) {
	ref, err := name.ParseReference(image)
	if err != nil {
		return "", fmt.Errorf("parsing image reference %q: %w", image, err)
	}
	desc, err := remote.Head(ref, append(c.options, remote.WithContext(ctx))...)
	if err != nil {
		return "", fmt.Errorf("resolving %s: %w", image, err)
	}
	return desc.Digest.String(), nil
}
