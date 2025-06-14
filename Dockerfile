# Build the manager binary
FROM --platform=$BUILDPLATFORM golang:1.24.3-alpine3.21 AS builder
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace

# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum

# Cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download

# Copy the go source
COPY main.go main.go
COPY agent/ agent/
COPY stage/ stage/

# Build
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GO111MODULE=on go build -a -o fluent-test main.go

# Use alpine tiny images as a base
FROM alpine:3.22.0

ENV USER_UID=2001 \
    USER_NAME=fluent-test \
    GROUP_NAME=fluent-test

WORKDIR /
RUN addgroup ${GROUP_NAME} && adduser -D -G ${GROUP_NAME} -u ${USER_UID} ${USER_NAME}

COPY --from=builder --chown=${USER_UID} /workspace/fluent-test .

USER ${USER_UID}

ENTRYPOINT ["/fluent-test"]
