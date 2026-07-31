# syntax=docker/dockerfile:1
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/argo-tag-watcher .

FROM alpine:3.20
# git is needed for `git ls-remote`; ca-certificates for TLS to the git host.
RUN apk add --no-cache git ca-certificates
COPY --from=build /out/argo-tag-watcher /usr/local/bin/argo-tag-watcher
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/argo-tag-watcher"]
