# Project Layout, Modules, Builds, Releases

Go's project structure is **boring on purpose**. The compiler-enforced rules are: one module per `go.mod`, `internal/` is private to the module subtree, `cmd/<name>/main.go` is convention not requirement, and that's it. Everything else is community taste.

The most common AI failure mode here is reaching for the unofficial `golang-standards/project-layout` repo. The Go team has never endorsed it, and the community has moved away from its heavier prescriptions (`pkg/` especially) for years. Russ Cox, Dave Cheney, Peter Bourgon, and the Go team's own writing all argue **flat is better, public at the module root, private in `internal/`**.

## The shape of a real project

For a multi-binary service:

```
my-service/
├── go.mod
├── go.sum
├── README.md
├── Dockerfile
├── .golangci.yml
├── .goreleaser.yaml
├── cmd/
│   ├── my-service/
│   │   └── main.go         # tiny main() → run()
│   └── my-service-migrate/
│       └── main.go
├── internal/
│   ├── config/
│   │   └── config.go
│   ├── http/
│   │   ├── server.go        # NewServer(deps) http.Handler
│   │   ├── routes.go        # one place for all route registration
│   │   └── middleware.go
│   ├── user/                # domain package — types + business logic
│   │   ├── user.go
│   │   ├── service.go
│   │   ├── store.go         # interface defined HERE (consumer-side)
│   │   └── service_test.go
│   ├── store/
│   │   └── postgres/
│   │       ├── postgres.go
│   │       └── queries.sql.go   # sqlc-generated
│   └── version/
│       └── version.go       # build-time -X stamps
├── db/
│   ├── migrations/
│   │   ├── 0001_init.up.sql
│   │   └── 0001_init.down.sql
│   ├── queries/
│   │   └── users.sql        # sqlc input
│   └── sqlc.yaml
├── deploy/
│   ├── helm/
│   └── k8s/
├── docs/
└── testdata/
```

For a single-binary library + CLI:

```
my-lib/
├── go.mod
├── README.md
├── doc.go                  // package docs
├── my-lib.go               // public API at module root
├── internal/
│   └── parser/
└── cmd/
    └── my-cli/
        └── main.go
```

For a library only:

```
my-lib/
├── go.mod
├── README.md
├── doc.go
├── retry.go               // public API at module root
├── retry_test.go
└── internal/
    └── jitter/
```

## What goes where

| Directory | Use |
|---|---|
| `cmd/<name>/` | One `main.go` per binary. The package is always `main`. The binary name comes from the directory name (`go install ./cmd/my-svc` → binary `my-svc`). |
| `internal/` | Everything that should not be importable outside this module. The compiler enforces this — a package outside the module tree gets `use of internal package ... not allowed`. **Default home for new code.** |
| **Module root** | Public API of a library. Don't put library code under `pkg/`; that's an antipattern. |
| `db/` (or `migrations/`) | SQL migrations, sqlc query files, schema. Not under `internal/` because it isn't Go code. |
| `deploy/` (or `deployments/`) | Helm charts, Kubernetes manifests, Terraform. |
| `testdata/` | Test fixtures. Special-cased by the Go toolchain: ignored by `go build`, available to tests via `os.ReadFile("testdata/foo.json")`. |
| `docs/` | Markdown docs that don't belong in `README.md`. |
| `scripts/` | Build/CI helper shell scripts. Bash skill applies. |
| `examples/` | Library-only: runnable example programs that show off the API. Each subdir is its own `package main`. |

## Why not `pkg/`

`pkg/foo/foo.go` makes consumers write `import ".../my-app/pkg/foo"`. The `/pkg/` segment carries no meaning — `internal/` already says "private," and anything not in `internal/` is public. `/pkg/` is decorative and the community calls it out:

- Dave Cheney: ["I don't see a reason for `pkg/` in a Go project."](https://dave.cheney.net/practical-go/presentations/qcon-china.html)
- Russ Cox in the original Go-modules announcement avoids it entirely.
- The Go standard library doesn't use it. `net/http`, `encoding/json` — all at the root of their tree.

The exception people cite: distinguishing reusable from non-reusable code in a polyglot monorepo. In a Go-only repo, this distinction doesn't exist — every public Go package is importable.

**Default: no `pkg/`.** Only use it if your team has a documented, specific reason.

## Packages, not directories

Go's import path resolution is filesystem-based, but packages are not directories. The rules:

- **One package per directory.** A directory contains files that all declare the same `package <name>`. (Exception: `*_test.go` files may declare `<name>_test` to live as a black-box test package alongside the white-box one.)
- **Package name = directory name** when possible. Match `package user` to directory `user/`. Avoid stutter (`user.User` reads worse than `user.Account`).
- **Avoid `package util` / `common` / `helpers` / `misc`.** Name packages by what they *provide*, not by what they are. `package retry` is good; `package retryutil` is noise.
- **Short, lowercase, no underscores, no camelCase.** `package json` not `package JSON`.

## Module path

The `module` directive in `go.mod` is the canonical import path. The convention:

```
module github.com/<org>/<repo>
```

It does not have to match the actual git host, but anything else surprises tools (`go get`, `go install`, vanity domains aside). For private modules, set `GOPRIVATE=github.com/myorg/*` so the toolchain doesn't try to talk to the public proxy/checksum DB.

For libraries that may be vendored or vendored-into:

- **Stable v0 / v1**: `module example.com/lib`
- **v2+ semantic import versioning**: `module example.com/lib/v2`. The `/v2` is part of the import path; consumers `import "example.com/lib/v2"`. Don't break the rule — it bypasses Go's minimum-version-selection guarantees.

## Workspaces — `go.work`

For multi-module development (libraries developed alongside their consumers):

```
my-monorepo/
├── go.work
├── server/
│   ├── go.mod
│   └── ...
└── lib/
    ├── go.mod
    └── ...
```

```
// go.work
go 1.25.0

use (
    ./server
    ./lib
)
```

In a workspace, the `server` module uses the local `./lib` instead of resolving the `require` to the network. Build tools (`go build`, `go test`) automatically detect `go.work` from the cwd.

**Don't commit `go.work` if CI should validate each module's own `go.mod`** independently. Either gitignore it (developer-only) or commit it deliberately and accept that CI must run against the workspace state. `GOWORK=off` disables workspace mode in a build, which is the canonical CI override.

## Vendoring

`go mod vendor` writes the entire dep tree to `./vendor/`. Subsequent builds use `vendor/` instead of the module cache. Use cases in 2026:

- **Air-gapped builds** (regulated environments).
- **Deterministic builds where the network can't be trusted**.
- **CI environments without module-cache persistence** where vendor materializes deps once per repo.

For most projects, **don't vendor.** `go.sum` already provides cryptographic tamper detection; the proxy provides availability. Vendoring inflates the repo size and noise of every dep upgrade.

## Build commands

```bash
go build ./...                    # all packages — discards binaries except in cmd/
go build -o bin/svc ./cmd/svc     # build a specific binary
go install ./cmd/svc              # build + install to $GOBIN
go run ./cmd/svc -flag=value      # build + run in one step
```

### Build flags for releases

The canonical "small static binary with version info" flags:

```bash
CGO_ENABLED=0 \
  go build \
    -trimpath \
    -buildvcs=true \
    -ldflags="-s -w -X main.version=$(git describe --tags --always --dirty)" \
    -tags="osusergo,netgo" \
    -o bin/svc \
    ./cmd/svc
```

What each does:

| Flag | Effect |
|---|---|
| `CGO_ENABLED=0` | No libc / no cgo. Binary is fully static, runs anywhere. |
| `-trimpath` | Strips the local file paths from compiled binaries (reproducibility + privacy). |
| `-buildvcs=true` | Embeds VCS info (commit, dirty flag) into the binary. Readable via `runtime/debug.ReadBuildInfo()`. Default since 1.18. |
| `-ldflags="-s -w"` | Strip symbol table (`-s`) and DWARF (`-w`). ~30% smaller binaries. Skip if you need to debug production. |
| `-ldflags="-X main.version=…"` | Set a `var version string` at link time. The canonical way to stamp build info. |
| `-tags="osusergo,netgo"` | Force the pure-Go `os/user` and `net` resolver. Avoids glibc dependency. |

For the version stamp:

```go
// internal/version/version.go
package version

import "runtime/debug"

var (
    Version   = "dev"
    Commit    = "unknown"
    BuildDate = "unknown"
)

func init() {
    if info, ok := debug.ReadBuildInfo(); ok {
        for _, s := range info.Settings {
            switch s.Key {
            case "vcs.revision":
                Commit = s.Value
            case "vcs.time":
                BuildDate = s.Value
            }
        }
    }
}
```

Then `-ldflags="-X .../internal/version.Version=v1.2.3"` and the runtime picks up the rest from `-buildvcs`.

## Reproducible builds

`-trimpath` is the headline. Beyond that, `goreleaser` v2 supports `mod_timestamp: "{{ .CommitTimestamp }}"` to make output bit-identical given the same source. For library authors publishing to module proxy, reproducibility is automatic (the proxy hashes the module tree).

## Releases — `goreleaser` v2

The 2026 standard release tool. Cross-compiles, archives, signs, uploads to GitHub/GitLab releases, builds container images, generates SBOMs, updates Homebrew/Scoop taps, all in one config:

```yaml
# .goreleaser.yaml
version: 2

before:
  hooks:
    - go mod tidy
    - go generate ./...

builds:
  - id: my-svc
    main: ./cmd/my-svc
    binary: my-svc
    env:
      - CGO_ENABLED=0
    flags:
      - -trimpath
    ldflags:
      - -s -w
      - -X github.com/me/my-svc/internal/version.Version={{ .Version }}
      - -X github.com/me/my-svc/internal/version.Commit={{ .Commit }}
      - -X github.com/me/my-svc/internal/version.BuildDate={{ .Date }}
    tags:
      - osusergo
      - netgo
    goos: [linux, darwin]
    goarch: [amd64, arm64]
    mod_timestamp: "{{ .CommitTimestamp }}"

archives:
  - formats: [tar.gz]
    name_template: "{{ .ProjectName }}_{{ .Version }}_{{ .Os }}_{{ .Arch }}"

checksum:
  name_template: "checksums.txt"

snapshot:
  version_template: "{{ incpatch .Version }}-next"

changelog:
  use: github
  sort: asc

kos:
  - repository: ghcr.io/me/my-svc
    tags: ["{{.Version}}", latest]
    bare: true
    preserve_import_paths: false
    base_image: "gcr.io/distroless/static-debian12:nonroot"
    platforms:
      - linux/amd64
      - linux/arm64
```

Run:

```bash
goreleaser release --clean        # tagged release
goreleaser release --snapshot     # untagged test build
goreleaser build --snapshot --single-target   # quick local build
```

The `kos:` block invokes `ko` (CNCF, Go-native container builder) to produce small distroless images without writing a Dockerfile. This is the 2026 default for Go service images.

## Containers — `distroless/static`

The 2026 standard:

```dockerfile
# Stage 1: build
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags="-s -w" \
    -tags="osusergo,netgo" \
    -o /out/svc ./cmd/svc

# Stage 2: minimal runtime
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/svc /svc
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/svc"]
```

Why distroless:

- Includes CA certs, tzdata, `/etc/passwd`.
- Runs as non-root by default (`:nonroot` tag).
- No shell, no package manager — drastically smaller attack surface.
- Reproducible: Google ships signed images.

Avoid `alpine` unless you need a shell — musl differences cause DNS/CGO bugs that don't show up in dev. Avoid `scratch` unless you also pull in `ca-certificates`.

If you're using `goreleaser` with the `kos` block above, you don't need a Dockerfile at all.

## CI for a Go project

The minimum-viable CI matrix:

```yaml
# .github/workflows/ci.yml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
          cache: true
      - run: go vet ./...
      - run: go test -race -shuffle=on -count=1 ./...

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
      - uses: golangci/golangci-lint-action@v6
        with:
          version: v2.x

  vuln:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: 'go.mod'
      - uses: golang/govulncheck-action@v1
```

`go-version-file: 'go.mod'` reads the `go` directive — no second source of truth for the version.

## What not to do

- **`pkg/`** as the default home for code. Use `internal/` for private, module root for public.
- **`golang-standards/project-layout`** as a literal blueprint. It's a community wiki, not a Go-team standard.
- **`util` / `common` / `helpers` / `misc` packages.** Name by what they provide.
- **`go.work` committed without intent.** Either commit it deliberately or gitignore.
- **Vendoring by default.** Use only when air-gapped or paranoid.
- **`tools.go`** for tracking dev dependencies. Use `go.mod` `tool` directive (1.24+).
- **`alpine` base images.** Use `distroless/static-debian12:nonroot`.
- **Hand-rolled Dockerfile when goreleaser+ko exists.** Skip the maintenance.
- **`v2+` modules without the `/v2` import path suffix.** The toolchain will silently use whichever it finds first; consumers get the wrong version.
- **Forking a public library to vendor it.** Use `replace` in `go.mod` for local patches, or vendor it explicitly.
- **`-ldflags` with hardcoded git output** (`$(git rev-parse HEAD)`) in a Dockerfile. The Docker build context may not have `.git`. Use `-buildvcs=true` and read it back via `debug.ReadBuildInfo`.
