package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// manifestAccept lists every manifest media type we are willing to be handed.
// Which one comes back matters for nothing except that the digest of the bytes
// is what a runtime records: for a single-platform image the tag resolves to a
// manifest, for a multi-arch build to an index, and containerd reports whichever
// one the tag pointed at.
//
// All four, because the list has to be complete: GHCR answers a request whose
// Accept omits the tag's actual type with 404, not 406, so a short list reads as
// "no such tag" and is indistinguishable from one. Even within our own registry
// the shapes differ -- docker manifest, OCI manifest and OCI index are all in use.
const manifestAccept = "application/vnd.oci.image.index.v1+json," +
	"application/vnd.docker.distribution.manifest.list.v2+json," +
	"application/vnd.oci.image.manifest.v1+json," +
	"application/vnd.docker.distribution.manifest.v2+json"

// DigestResolver resolves an image reference to the digest its tag points at.
type DigestResolver interface {
	Digest(ctx context.Context, image string) (string, error)
}

// registryClient reads manifests from an OCI registry over the distribution API.
// It sends no credentials of its own and answers a Bearer challenge anonymously,
// which is what the public GHCR packages we watch need; a registry demanding real
// credentials will fail the token request and the workload is left alone.
type registryClient struct {
	http   *http.Client
	scheme string // "https" in production; tests point it at an httptest server
}

func newRegistryClient() *registryClient {
	return &registryClient{
		http:   &http.Client{Timeout: 30 * time.Second},
		scheme: "https",
	}
}

// Digest fetches the manifest the tag points at and returns its digest. The
// digest of a manifest is defined as the sha256 of its bytes, so we compute it
// rather than trusting the registry's Docker-Content-Digest header.
func (c *registryClient) Digest(ctx context.Context, image string) (string, error) {
	host, repo, tag, err := parseImageRef(image)
	if err != nil {
		return "", err
	}
	url := fmt.Sprintf("%s://%s/v2/%s/manifests/%s", c.scheme, host, repo, tag)

	resp, err := c.fetch(ctx, url, "")
	if err != nil {
		return "", err
	}
	if resp.StatusCode == http.StatusUnauthorized {
		challenge := resp.Header.Get("WWW-Authenticate")
		resp.Body.Close()
		token, err := c.token(ctx, challenge)
		if err != nil {
			return "", fmt.Errorf("authenticating for %s: %w", image, err)
		}
		if resp, err = c.fetch(ctx, url, token); err != nil {
			return "", err
		}
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GET %s: %s", url, resp.Status)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return "", fmt.Errorf("reading manifest for %s: %w", image, err)
	}
	sum := sha256.Sum256(body)
	return "sha256:" + hex.EncodeToString(sum[:]), nil
}

func (c *registryClient) fetch(ctx context.Context, url, token string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", manifestAccept)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return c.http.Do(req)
}

// token answers a Bearer challenge -- `Bearer realm="...",service="...",scope="..."`
// -- by asking the named realm for an anonymous token.
func (c *registryClient) token(ctx context.Context, challenge string) (string, error) {
	params := parseChallenge(challenge)
	realm := params["realm"]
	if realm == "" {
		return "", fmt.Errorf("no realm in challenge %q", challenge)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, realm, nil)
	if err != nil {
		return "", err
	}
	q := req.URL.Query()
	for _, k := range []string{"service", "scope"} {
		if v := params[k]; v != "" {
			q.Set(k, v)
		}
	}
	req.URL.RawQuery = q.Encode()

	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GET %s: %s", realm, resp.Status)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", err
	}
	return tokenFromJSON(string(body))
}

// parseChallenge splits a `Bearer k="v",k="v"` header into its parameters.
func parseChallenge(challenge string) map[string]string {
	out := map[string]string{}
	rest := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(challenge), "Bearer"))
	for _, part := range splitOutsideQuotes(rest) {
		k, v, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok {
			continue
		}
		out[k] = strings.Trim(v, `"`)
	}
	return out
}

// splitOutsideQuotes splits on commas that are not inside a quoted value; a
// scope like `repository:a/b:pull,push` carries one.
func splitOutsideQuotes(s string) []string {
	var parts []string
	var cur strings.Builder
	inQuotes := false
	for _, r := range s {
		switch {
		case r == '"':
			inQuotes = !inQuotes
			cur.WriteRune(r)
		case r == ',' && !inQuotes:
			parts = append(parts, cur.String())
			cur.Reset()
		default:
			cur.WriteRune(r)
		}
	}
	if cur.Len() > 0 {
		parts = append(parts, cur.String())
	}
	return parts
}

// tokenFromJSON pulls the token out of a token-endpoint response. Registries
// return it as `token`; some also (or only) use `access_token`.
func tokenFromJSON(body string) (string, error) {
	var parsed struct {
		Token       string `json:"token"`
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal([]byte(body), &parsed); err != nil {
		return "", fmt.Errorf("parsing token response: %w", err)
	}
	if parsed.Token != "" {
		return parsed.Token, nil
	}
	if parsed.AccessToken != "" {
		return parsed.AccessToken, nil
	}
	return "", fmt.Errorf("token response carried no token")
}

// parseImageRef splits an image reference into the registry host to query, the
// repository path and the tag. A reference already pinned to a digest has
// nothing to resolve and is rejected.
func parseImageRef(image string) (host, repo, tag string, err error) {
	if strings.Contains(image, "@") {
		return "", "", "", fmt.Errorf("%q is digest-pinned", image)
	}
	rest := image
	tag = "latest"
	// A colon after the last slash is the tag; one before it is a registry port.
	if i := strings.LastIndex(rest, ":"); i > strings.LastIndex(rest, "/") {
		rest, tag = rest[:i], rest[i+1:]
	}
	first, remainder, hasSlash := strings.Cut(rest, "/")
	switch {
	case hasSlash && (strings.ContainsAny(first, ".:") || first == "localhost"):
		host, repo = first, remainder
	case !hasSlash:
		// A bare name like `nginx` is a Docker Hub official image.
		host, repo = "registry-1.docker.io", "library/"+rest
	default:
		host, repo = "registry-1.docker.io", rest
	}
	if host == "docker.io" {
		host = "registry-1.docker.io"
	}
	if repo == "" || tag == "" {
		return "", "", "", fmt.Errorf("cannot parse image reference %q", image)
	}
	return host, repo, tag, nil
}
