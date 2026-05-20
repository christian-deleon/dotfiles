# Tooling

The Go toolchain *is* the build system, package manager, formatter, test runner, and module resolver. There is no `package.json`, no virtualenv, no separate dependency tool. The 2026 stack adds a small set of well-aged third-party utilities: `gofumpt` (stricter formatter), `golangci-lint` v2 (lint aggregator), `gopls` (LSP), `govulncheck` (CVE scanner), `delve` (debugger), and `goreleaser` v2 (release packager). Everything else is the language.

The most common AI failure mode here is using `gofmt` alone (gofumpt has been the de-facto formatter since 2023), running tests without `-race`, or reaching for `tools.go` to track CLI dependencies (the `tool` directive in `go.mod` superseded that in 1.24).

## `go` — the only build system you need

```bash
go mod init github.com/me/my-app    # create go.mod
go get github.com/jackc/pgx/v5      # add a dep (latest)
go get github.com/jackc/pgx/v5@v5.7.0   # pin a version
go get -u ./...                     # upgrade everything within constraints
go mod tidy                         # remove unused deps, fill go.sum
go mod download                     # populate the module cache
go mod why github.com/x/y           # explain why a module is in the graph
go mod graph | grep …               # raw dependency edges

go build ./...                      # build all packages
go install ./cmd/myapp              # install to $GOBIN
go run ./cmd/myapp -flag=value      # build + run; great in dev
go vet ./...                        # built-in static analysis (always passes)
go test ./...                       # run all tests
go test -race -shuffle=on ./...     # canonical CI invocation
go test -run TestFoo -v ./pkg/...   # filter + verbose
go test -bench=. -benchmem ./...    # benchmarks with allocation stats
go test -fuzz=FuzzParse -fuzztime=30s ./parser   # fuzz for 30s
go generate ./...                   # run `//go:generate` directives
go work init ./moduleA ./moduleB    # multi-module workspace
go env -w GOFLAGS='-trimpath'       # persist a default flag
```

### `go.mod` and toolchains

```
module github.com/me/my-app

go 1.25.0           // language version; what features you can use
toolchain go1.26.3  // (optional) minimum toolchain; downloaded if not present

require (
    github.com/jackc/pgx/v5 v5.7.0
    golang.org/x/sync v0.10.0
)

tool (
    github.com/golangci/golangci-lint/v2/cmd/golangci-lint
    github.com/sqlc-dev/sqlc/cmd/sqlc
)
```

- **`go` directive** = language version. As of Go 1.26, `go mod init` writes `go 1.25.0` (N-1) for compatibility. Bump it deliberately when you start using a feature.
- **`toolchain` directive** = minimum compiler. `GOTOOLCHAIN=auto` (default) downloads it if missing. `GOTOOLCHAIN=local` disables auto-download — use in CI to fail fast on toolchain drift.
- **`tool` directive** (1.24+) — track CLI dependencies (linters, codegen, mockers). Replaces the old `tools.go` blank-import hack:
  ```bash
  go get -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint
  go tool golangci-lint run ./...
  ```

### Versions and support

Only the current and previous minors get security fixes. As of May 2026: **1.26.x** (current), **1.25.x** (previous). Anything older is unsupported. Target `go 1.25.0` as your floor unless you have a reason to require 1.26-only features.

Don't downgrade the `go` directive to support an old Go installation — `GOTOOLCHAIN=auto` will pull the right one. The `go` line is "what features may this code use," not "what version is installed."

## Formatting — `gofumpt` (+ `goimports`)

`gofumpt` is a strict superset of `gofmt` that the community has standardized on since 2023. It tightens a handful of cases `gofmt` left ambiguous (composite literal layout, single-statement blocks, octal literals). It's bundled into `gopls` — most editors run it on save.

```bash
go install mvdan.cc/gofumpt@latest
gofumpt -l -w .              # format files in place; list changed files
goimports -l -w .            # group/sort imports (stdlib, third-party, local)
```

In `gopls` config (e.g., `~/.config/gopls/config.json` or VS Code settings):

```json
{
  "gopls": {
    "formatting.gofumpt": true,
    "ui.completion.usePlaceholders": true,
    "ui.diagnostic.staticcheck": true
  }
}
```

`gofmt` is still legal — `gofumpt` output passes `gofmt -d`. But `gofumpt` is what every reviewer in 2026 expects.

## Linting — `golangci-lint` v2

The 2026 lint aggregator. v2 (released early 2025) reworked configuration — the `linters.default: standard|all|none|fast` knob replaces the v1 `enable-all`/`disable-all` mess. Migrate v1 configs with `golangci-lint migrate`.

```bash
go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
golangci-lint run ./...           # default preset
golangci-lint run --fix ./...     # apply auto-fixes
golangci-lint cache clean         # nuke cache after upgrades
```

Minimal `.golangci.yml`:

```yaml
version: "2"

linters:
  default: standard
  enable:
    - errcheck
    - errorlint
    - gocritic
    - gosec
    - govet
    - ineffassign
    - misspell
    - revive
    - staticcheck
    - unused

  settings:
    revive:
      rules:
        - name: exported
        - name: unused-parameter
    gosec:
      excludes:
        - G104   # unhandled errors — errcheck owns this
    gocritic:
      enabled-tags:
        - performance
        - style
        - diagnostic

  exclusions:
    rules:
      - path: _test\.go
        linters: [gosec, errcheck]   # tests can be a bit looser
```

Common linters worth knowing:

- **`errcheck`** — every returned `error` must be assigned or explicitly discarded with `_`. The single most valuable lint.
- **`staticcheck`** — Dominik Honnef's analyzer suite. Detects real bugs.
- **`errorlint`** — flags `err == ErrX` on wrapped errors, missing `%w`, type assertions on errors.
- **`govet`** — built-in. Catches `copylocks` (copying a `sync.Mutex`), `printf` (format mismatches), `shadow`, `loopclosure` (much less useful in 1.22+).
- **`revive`** — fast replacement for the deprecated `golint`. Enforces style/naming.
- **`gosec`** — security smells (`G112` unbounded `ReadHeaderTimeout`, `G304` path injection, etc).
- **`gocritic`** — broad style + diagnostic checks.
- **`misspell`** — typos in comments/strings.

Run in CI on every PR. Treat as required.

## `gopls` — LSP server

`gopls` is the canonical Go language server. Editor integrations (VS Code Go extension, Neovim LSP, JetBrains GoLand) all consume it. Beyond completions and diagnostics, `gopls` offers refactorings:

- **Rename** (`gopls rename`) — type-aware, cross-package.
- **Extract function / extract variable** — pull a selection into a named symbol.
- **Inline call** — opposite of extract.
- **Stub interface methods** — given `var _ Foo = (*Bar)(nil)`, fill in unimplemented methods on `*Bar`.
- **Fill struct** — populate all fields with zero values.
- **Move parameter** — reorder function parameters with all call sites updated.

Update with `go install golang.org/x/tools/gopls@latest`. Misbehaving editors? `gopls -rpc.trace` to see what the editor is asking for.

## `govulncheck` — vulnerability scanning

Lightweight CVE scanner from the Go security team. Reads the Go vuln DB and reports only on symbols you actually call (not just present in the dep graph):

```bash
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...                 # scan everything
govulncheck -mode=binary ./mybin  # scan a built binary
```

In CI:

```yaml
- uses: golang/govulncheck-action@v1
  with:
    go-version-file: 'go.mod'
```

Non-zero exit on findings; fail the pipeline. Optionally `upload-sarif: true` to surface in GitHub Code Scanning.

## `delve` — debugger

```bash
go install github.com/go-delve/delve/cmd/dlv@latest
dlv debug ./cmd/myapp -- --flag value     # build + debug
dlv test ./pkg/...                         # debug tests
dlv attach <pid>                           # attach to running process
dlv exec ./bin/myapp                       # debug a compiled binary
```

Editor integrations (VS Code, Neovim) wrap dlv via DAP. For one-off bug hunting, `dlv` interactive REPL is fast.

## Tests

### The canonical invocation

```bash
go test -race -shuffle=on -count=1 ./...
```

- **`-race`** — non-negotiable in CI. Costs ~2× runtime + ~5× memory; worth every byte.
- **`-shuffle=on`** — randomize test order within a package. Catches order-dependent leakage.
- **`-count=1`** — disables result caching. Use when you want a guaranteed re-run; omit in normal dev.

### Table-driven tests

The canonical shape. `t.Parallel()` inside each subtest:

```go
func TestParseDuration(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		input   string
		want    time.Duration
		wantErr bool
	}{
		{"seconds", "10s", 10 * time.Second, false},
		{"minutes", "5m", 5 * time.Minute, false},
		{"invalid", "abc", 0, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := ParseDuration(tt.input)
			if (err != nil) != tt.wantErr {
				t.Fatalf("ParseDuration(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			}
			if got != tt.want {
				t.Errorf("ParseDuration(%q) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}
```

Go 1.22's per-iteration loop variable scoping eliminated the historic `tt := tt` shadowing line. Drop it in new code.

### `testing/synctest` (1.25+ stable)

Tests for time-dependent or concurrent code without real sleeping. `synctest` virtualizes the clock and waits for all goroutines in the bubble to be blocked:

```go
import "testing/synctest"

func TestRetryBackoff(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		start := time.Now()

		client := NewClient(WithBackoff(time.Second))
		_ = client.Do(ctx, "fail-3-times")

		// "Three retries with 1s, 2s, 4s backoff" — real time elapsed: ~0ms.
		if got := time.Since(start); got != 7*time.Second {
			t.Errorf("elapsed = %v, want 7s", got)
		}
	})
}
```

Replaces the entire "sleep and hope" testing genre. Was `GOEXPERIMENT=synctest` in 1.24; promoted to stable API in 1.25.

### Benchmarks — `b.Loop` (1.24+)

```go
func BenchmarkParse(b *testing.B) {
	input := []byte(`{"x": 1, "y": 2}`)
	for b.Loop() {
		_, _ = Parse(input)
	}
}
```

`b.Loop()` replaces the manual `for i := 0; i < b.N; i++` and the implicit `b.ResetTimer` dance. The runtime adaptively sizes iterations. Pair with `-benchmem` for allocation reporting.

### Fuzz

```go
func FuzzParse(f *testing.F) {
	f.Add([]byte(`{"x": 1}`))    // seed corpus
	f.Add([]byte(`null`))
	f.Fuzz(func(t *testing.T, data []byte) {
		v, err := Parse(data)
		if err != nil {
			return
		}
		out, err := Marshal(v)
		if err != nil {
			t.Fatalf("Marshal(%q): %v", data, err)
		}
		// roundtrip property
		v2, err := Parse(out)
		if err != nil || !equal(v, v2) {
			t.Fatalf("roundtrip failed for %q", data)
		}
	})
}
```

Run locally with `go test -fuzz=FuzzParse -fuzztime=30s`. Mature for parsers, decoders, and protocol code; less common for business logic.

### Goroutine leak detection — `uber-go/goleak`

```go
import "go.uber.org/goleak"

func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m)
}
```

Fails the test run if any goroutine survives a test. Catches forgotten cancellations and hung receivers. Drop into every service's test suite.

### Integration tests — `testcontainers-go`

Stand up Postgres / Redis / Kafka per-test-package, no Docker Compose:

```go
import (
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
)

func TestRepository_Integration(t *testing.T) {
	ctx := context.Background()
	pg, err := postgres.Run(ctx, "postgres:17-alpine",
		postgres.WithDatabase("test"),
		postgres.WithUsername("test"),
		postgres.WithPassword("test"),
		postgres.BasicWaitStrategies(),
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = pg.Terminate(ctx) })

	dsn, _ := pg.ConnectionString(ctx, "sslmode=disable")
	// ... run real queries against pg
}
```

Standard in 2026 for any non-trivial DB-backed service.

### HTTP handler tests

`httptest.NewRecorder` for a single handler's unit test:

```go
func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest("GET", "/health", nil)
	rr := httptest.NewRecorder()
	HealthHandler(rr, req)
	if rr.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", rr.Code)
	}
}
```

`httptest.NewServer` when you want to exercise routing + middleware end-to-end (Mat Ryer's preferred shape — call `run()` then hit it).

### Assertions — stdlib or `testify`

Split community:

- **stdlib only** — `t.Errorf` / `t.Fatalf` with explicit messages. Most idiomatic. Add small helpers (`equal(t, got, want)`) where useful.
- **`stretchr/testify`** — still the most-used assertion library by a wide margin (`assert.Equal`, `require.NoError`). Brings fluent assertions; trades verbosity for diff quality on failures.
- **`matryer/is`** — minimalist alternative (`is.NoErr(err)`, `is.Equal(got, want)`). Used in Mat Ryer's own code.

Pick stdlib for new code; switch to `testify` or `is` if the team prefers fluent. Don't mix them within one repo.

## Mocking

The default reflex is **don't mock**. Define interfaces in the consumer narrowly enough that hand-written fakes are trivial:

```go
type UserStore interface {
	Get(ctx context.Context, id int) (User, error)
}

type fakeUserStore struct {
	users map[int]User
	err   error
}

func (f *fakeUserStore) Get(_ context.Context, id int) (User, error) {
	if f.err != nil {
		return User{}, f.err
	}
	u, ok := f.users[id]
	if !ok {
		return User{}, ErrNotFound
	}
	return u, nil
}
```

When the interface surface is too large for hand-writing, generate:

- **`go.uber.org/mock`** (maintained fork of archived `golang/mock`) — `mockgen` style; explicit `EXPECT()` calls. Fine but verbose.
- **`matryer/moq`** — generates plain structs with field-set function fields. Smaller, simpler, no `EXPECT` ceremony.

Either way, prefer fakes for anything you'll exercise in many tests; reserve mocks for "this call must happen with these arguments" assertions.

## What not to do

- **`gofmt`-only repo** in 2026 — `gofumpt` is the de-facto bar.
- **`tools.go`** blank imports — use the `go.mod` `tool` directive.
- **`go get -u all`** without testing — upgrades transitive deps; pin to specific versions in CI.
- **`go.sum` not committed.** Always commit it. CI uses it to detect tampering.
- **Tests without `-race`.** A single bug discovered by the race detector pays for years of CI runtime.
- **`golint`** — deprecated since 2020; `revive` is the replacement.
- **`gocyclo`/`gocognit` alone** as a quality bar — produces low-value PRs. Use as part of `gocritic` if at all.
- **`vendor/` directory** for normal services — only when air-gapped or CI-isolated. `go.sum` already hashes dependencies for tamper detection.
- **Suppressing lints with `//nolint:...` without a justification comment** — `//nolint:errcheck // reason: …` is mandatory.
- **Letting `go vet` fail** — it's part of `go test` since 1.10, always passes on green builds. A failure indicates a real bug.
