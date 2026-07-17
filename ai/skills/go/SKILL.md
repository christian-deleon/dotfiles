---
name: go
description: Modern Go (1.25+) for services, CLIs, libraries — idioms, layout, concurrency, generics, testing. Use when editing `*.go`/`go.mod`, files under `cmd/` or `internal/`, or for prompts about goroutines, context, slog, errors.Is/As, gin, chi, pgx, sqlc, cobra, kong. Stack: gofumpt + golangci-lint v2 + govulncheck, stdlib `net/http`, `pgx/v5` + `sqlc`.
compatibility: opencode
---

# Go

Go is a small language with strong opinions and a culture that rewards reading the standard library before writing your own version of anything. The toolchain is the language: `go build`, `go test`, `go vet`, `gofmt`, `gopls`, and `go mod` are part of "how Go code works," not optional add-ons. New code in 2026 looks meaningfully different from new code in 2020 — generics, `log/slog`, `errors.Is`/`As`, `iter` package, `for range int`, 1.22+ pattern routing, `sync.WaitGroup.Go`, `testing/synctest`. The cheat sheets below assume you're writing for the current toolchain.

The most common AI failure mode here is writing 2018-era Go: `interface{}` instead of `any`, `for i := 0; i < n; i++` for simple counters, hand-rolled `Contains`/`Sort` instead of `slices.*`, `log.Printf` instead of `slog`, `errors.New(fmt.Sprintf(...))` instead of `fmt.Errorf("...: %w", err)`, ignored errors via `_`, premature interface definition at the producer ("I"-prefix Java-isms), `panic` for expected failures, naked `go fn()` without lifecycle ownership, `wg.Add(1)` inside the goroutine, `http.DefaultClient` (no timeout), `gin` or `gorm` on a new service. Don't do any of that. The defaults below are non-negotiable for new code.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Set up a module, pick tools, lint, format, test | [tooling.md](tooling.md) |
| Choose layout, write `cmd/`/`internal/`, build, release | [project-layout.md](project-layout.md) |
| Use generics, interfaces, embedding, iterators | [types.md](types.md) |
| Wrap, inspect, aggregate, or recover from errors | [errors.md](errors.md) |
| Write goroutines, use `errgroup`, `context`, `sync.WaitGroup.Go` | [concurrency.md](concurrency.md) |
| Build an HTTP service, route, log, connect to Postgres | [web.md](web.md) |
| Containerize as a distroless image — multi-stage, cache mounts, multi-arch, signing | [project-layout.md](project-layout.md) → "Containers" section. Universal Dockerfile/Compose/build/supply-chain patterns live in the [`docker`](../docker/SKILL.md) skill |

For one-off edits, the cheat sheets below are usually enough. Reach for the reference files when the task warrants depth.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Go version | **1.26** (floor: 1.25) | Only 1.26.x and 1.25.x get security/bug fixes. Older modules get a warning from `go mod`. |
| Toolchain pinning | `go` + `toolchain` lines in `go.mod`; `GOTOOLCHAIN=auto` | `go.mod init` defaults to N-1 (`go 1.25.0` on a 1.26 toolchain) for compatibility. |
| Format | **`gofumpt`** | Stricter superset of `gofmt`; integrated into `gopls`. Run on save. |
| Imports | **`goimports`** | Pair with `gofumpt` (`gopls` does both). |
| Lint | **`golangci-lint` v2** with `linters.default: standard` | Plus `errcheck`, `staticcheck`, `revive`, `gosec`, `errorlint`, `gocritic`, `misspell`. |
| Vuln scan | **`govulncheck`** in CI | `golang/govulncheck-action@v1`, fail on non-zero. |
| Type / LSP | **`gopls`** | Rename, extract, inline, stub interface, fill struct. |
| Debugger | **`delve`** | `dlv` for interactive; `dlv test` for tests. |
| Tests | **`go test -race -shuffle=on`** | `t.Parallel()` inside subtests; `testing.B.Loop` for benches. |
| Concurrent tests | **`testing/synctest`** (stable in 1.25) | Deterministic time/scheduling. |
| Leak detection | **`uber-go/goleak`** | `goleak.VerifyTestMain(m)` in `TestMain`. |
| Mocking | hand-written fakes by default; **`matryer/moq`** or `go.uber.org/mock` for surfaces | Resist `mockgen`-everything. |
| HTTP server | **stdlib `net/http`** (1.22+ pattern routing) | `chi` only if you need its middleware ecosystem. |
| HTTP client | **stdlib `*http.Client`** with explicit `Timeout` + tuned `Transport` | Never `http.DefaultClient`/`http.Get`. |
| Retries | **`hashicorp/go-retryablehttp`** | Or `cenkalti/backoff/v4` for non-HTTP. |
| Logging | **`log/slog`** (stdlib) | JSON handler in prod, text in dev. `otelslog` for trace IDs. |
| Config | **`caarlos0/env/v11`** (env-first) | `koanf` for multi-source; `viper` only if already on `cobra`. |
| DB (Postgres) | **`pgx/v5`** + **`sqlc`** | Avoid ORMs for greenfield. |
| Migrations | **`pressly/goose`** | `ariga.io/atlas` for declarative schema. |
| CLI | **`spf13/cobra`** (distributed) or **`alecthomas/kong`** (internal) | `flag` for small scripts. |
| Tracing/metrics | **OpenTelemetry Go SDK** (`go.opentelemetry.io/otel`) | `otelhttp`, `otelpgx`, `otelslog`. |
| Container base | **`gcr.io/distroless/static-debian12:nonroot`** | Build with `CGO_ENABLED=0 -trimpath -ldflags="-s -w"`. |
| Release | **`goreleaser` v2** | `mod_timestamp` for reproducible builds. |

## Header / preamble

The 2026 canonical shape for a binary is **Mat Ryer's `run()` pattern** — a tiny `main` that delegates to a testable `run(ctx, args, stdout, stderr) error`. Identical shape for HTTP services and CLIs:

```go
package main

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	if err := run(ctx, os.Args, os.Stdout, os.Stderr); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string, stdout, stderr io.Writer) error {
	logger := slog.New(slog.NewJSONHandler(stderr, nil))
	slog.SetDefault(logger)

	// parse args, wire deps, start server / do work
	return nil
}
```

Why this shape:

- **Testable.** `run()` takes its inputs and is callable from `_test.go`. `main` is the boring shell.
- **Graceful shutdown.** `signal.NotifyContext` ties `Ctrl+C` / `SIGTERM` to the `ctx` everything else watches.
- **No globals.** Logger, config, and clients are constructed inside `run()` and threaded through.

A library file is even simpler — `package <name>`, no `main`, no `run`:

```go
// Package retry implements bounded-exponential retry with jitter.
package retry

import "time"

// Backoff returns the delay before the n-th retry.
func Backoff(n int, base, cap time.Duration) time.Duration {
	// ...
}
```

Public identifiers get a **dense** doc comment that starts with the identifier name — purpose and non-obvious constraints, not a restatement of the signature or a walkthrough of the body. `gopls`, `golint`, and `revive` enforce the presence of the comment; density is on you. Inline comments explain *why*, never *what*; delete process/migration/restatement slop on sight (see the `no-comment-slop` rule).

## Modern syntax cheat sheet (1.22 → 1.26)

| Use | Don't use |
|---|---|
| `any` | `interface{}` |
| `for i := range 10` (1.22) | `for i := 0; i < 10; i++` for plain counting |
| `for range items` when index unused | `for _, _ = range items` |
| `slices.Sort(s)`, `slices.Contains(s, x)`, `slices.Index`, `slices.SortFunc` | hand-rolled sort/contains loops |
| `maps.Keys(m)`, `maps.Values(m)` (returns `iter.Seq` in 1.23+; `slices.Collect` to materialize) | hand-rolled key/value extraction |
| `min(a, b, ...)`, `max(a, b, ...)`, `clear(s)` (1.21 builtins) | hand-rolled helpers |
| `cmp.Or(a, b, c)` (1.22) — first non-zero | `if a != "" { … } else if b != "" { … }` |
| `cmp.Ordered`, `cmp.Compare[T]` (stdlib) | `golang.org/x/exp/constraints.Ordered` |
| `mux.HandleFunc("GET /items/{id}", h)` (1.22) | gorilla/mux for trivial routing |
| `log/slog` (stdlib) | `log.Printf`, `fmt.Println` for diagnostics |
| `fmt.Errorf("loading %s: %w", name, err)` | `fmt.Errorf("loading %s: %v", name, err)` when callers may `Is`/`As` |
| `errors.Is(err, fs.ErrNotExist)` / `errors.As(err, &target)` | `err == ErrFoo` / `err.(*MyErr)` |
| `errors.Join(errs...)` (1.20) | hand-rolled `[]error` flattening |
| `errors.AsType[*PathError](err)` (1.26) | `var pe *PathError; errors.As(err, &pe)` (still legal, just verbose) |
| `wg.Go(func(){ … })` (1.25 — `sync.WaitGroup.Go`) | `wg.Add(1); go func(){ defer wg.Done(); … }()` |
| `sync.OnceFunc(f)` / `OnceValue` / `OnceValues` (1.21) | manual `sync.Once` + closed-over result |
| `context.WithCancelCause(ctx)` + `context.Cause(ctx)` (1.20) | bare `WithCancel` when reasons matter |
| `errgroup.WithContext(ctx)` + `g.SetLimit(n)` (1.20) | hand-rolled bounded fan-out |
| `iter.Seq[T]` / `iter.Seq2[K,V]` return types (1.23) for streams | returning unbounded slices |
| `for x := range it` over an iterator (1.23) | manual `next/done` channel patterns |
| Generic type alias `type Set[T comparable] = map[T]struct{}` (1.24) | redeclaring the same map type everywhere |
| `b.Loop()` benchmark loop (1.24) | `for i := 0; i < b.N; i++` |
| `testing/synctest.Test(t, func(t *testing.T) { … })` (1.25 stable) | sleeping in tests to wait for timers |
| `os.Root` (1.24) for filesystem sandboxing | hand-rolled path checks against `..` |

## Error handling — the basics

The Go team **closed all error-syntax proposals in June 2025**. `if err != nil { return err }` is the permanent idiom, not a wart awaiting a fix. The full pattern is in [errors.md](errors.md); the headline:

```go
if err := db.Query(ctx, q); err != nil {
	return fmt.Errorf("query users: %w", err)
}
```

- **Wrap with `%w`** when callers might `Is`/`As` the underlying error. Use `%v` only when you specifically want to flatten the chain (rare).
- **Inspect with `errors.Is` / `errors.As`** (or `errors.AsType[T](err)` in 1.26+). Never type-assert directly on a wrapped error — that defeats `%w`.
- **`errors.Join(errs...)`** for aggregating multi-failure paths (validating N fields, closing N resources).
- **Sentinel errors** for identity matching (`var ErrNotFound = errors.New("not found")`). **Typed errors** for structured fields callers need. Both are legitimate; pick by what callers need to extract.
- **Panic only for unrecoverable programmer bugs** (nil deref, impossible default case, broken invariants). Library code returns errors.

Deferred close idiom — preserves both the primary error and the close error:

```go
func process(name string) (err error) {
	f, err := os.Open(name)
	if err != nil {
		return fmt.Errorf("open %s: %w", name, err)
	}
	defer func() { err = errors.Join(err, f.Close()) }()
	// ...
	return nil
}
```

## Concurrency — the basics

Every goroutine needs a clear owner and a clear exit. The 2026 canonical primitive is `errgroup` for fan-out work, `context` for lifecycle, and `sync.WaitGroup.Go` (1.25+) for fire-and-collect. Full patterns in [concurrency.md](concurrency.md); the headline:

```go
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(8)
for _, item := range items {
	item := item // unnecessary in 1.22+; harmless. Drop in new code.
	g.Go(func() error {
		return process(ctx, item) // first error cancels ctx; siblings unwind
	})
}
if err := g.Wait(); err != nil {
	return fmt.Errorf("processing items: %w", err)
}
```

Rules:

- **`context.Context` is the first argument**, named `ctx`. Never stored in a struct.
- **Every `WithCancel`/`WithTimeout`/`WithDeadline` is followed by `defer cancel()`.** No exceptions.
- **No naked `go fn()`** without a lifecycle owner. The owner is either `errgroup.Group`, `sync.WaitGroup`, or — for an indefinitely-running supervisor — a goroutine that explicitly listens to `ctx.Done()`.
- **`go test -race` in CI.** Non-negotiable.
- **`time.After` timer leak in tight loops is fixed in 1.23+**, but reusing a `time.NewTimer` is still better for hot paths.

## Stdlib reflexes worth knowing

| Use | Instead of |
|---|---|
| `slices.Sort`, `slices.Contains`, `slices.SortFunc`, `slices.Compact` | hand-rolled `sort.Slice` + loops |
| `maps.Keys`, `maps.Values`, `maps.Clone`, `maps.Equal` | hand-rolled |
| `cmp.Or`, `cmp.Ordered`, `cmp.Compare` | golang.org/x/exp/constraints |
| `sync.OnceFunc`, `OnceValue`, `OnceValues` | bare `sync.Once` + captured closures |
| `errors.Is`, `errors.As`, `errors.Join`, `errors.AsType` (1.26) | type assertions on errors |
| `context.WithCancelCause`, `context.Cause` | losing the "why" of cancellation |
| `signal.NotifyContext` | manual `os/signal.Notify` + `chan os.Signal` plumbing |
| `iter.Seq[T]`, `iter.Seq2[K,V]` for lazy streams | returning channels for collection iteration |
| `unique.Make[T]` for canonicalization (1.23) | hand-rolled interning maps |
| `os.Root` for sandboxed FS access (1.24) | path traversal checks |
| `weak.Pointer[T]` (1.24) for caches with GC-aware references | manual finalizers |
| `testing/synctest.Test` (1.25) for time-dependent tests | `time.Sleep` to wait for timers |
| `b.Loop()` benchmarks (1.24) | `for i := 0; i < b.N; i++` |
| `log/slog` with `slog.SetDefault` once at startup | configuring a global `log` everywhere |
| `http.ServeMux` with method+path patterns (1.22) | gorilla/mux, chi-for-trivial-cases |

## Universal rules

These apply across services, CLIs, and libraries:

1. **`any`, never `interface{}`.** New code, no exceptions.
2. **Errors wrap with `%w`** when callers might inspect them. Wrap message says what *this* layer was doing ("query users: %w", not "failed: %w").
3. **`context.Context` is the first parameter on every function that does I/O or blocks.** Never stored in a struct. Always `defer cancel()` after `WithCancel`/`WithTimeout`/`WithDeadline`.
4. **No goroutine without a lifecycle owner.** `errgroup.Group`, `sync.WaitGroup`, or a supervisor goroutine that listens to `ctx.Done()`.
5. **Define interfaces at the consumer**, not the producer. "Accept interfaces, return structs" is still the heuristic. Don't pre-emptively wrap a single concrete type in an interface "for testing."
6. **`log/slog` for all diagnostics.** No `fmt.Println`, no `log.Printf`. CLIs may write their actual output to stdout; logs go to stderr via `slog`.
7. **Always set HTTP timeouts.** `http.Server.ReadHeaderTimeout` is mandatory (`gosec` G112). Never `http.DefaultClient` / `http.Get` in production code.
8. **`gofumpt` formatted, `golangci-lint` (v2 standard preset + extras) clean, `go test -race -shuffle=on` green, `govulncheck` zero in CI.** The bar is "all four pass."
9. **`go.mod` `tool` directive** (1.24+) tracks dev tools (`golangci-lint`, `mockgen`, `sqlc`). Drop `tools.go`.
10. **Reproducible builds**: `-trimpath -ldflags="-s -w -X main.version=…" -tags="osusergo,netgo"` with `CGO_ENABLED=0`.

## When Go isn't the right tool

Switch languages when you hit any of:

- A hot numerical loop where SIMD or autovectorization would matter — Rust, C, or Zig. Go's compiler is not aggressive about vectorization.
- A latency tail you can't tolerate due to GC pauses — even the 1.26 Green Tea GC has pauses; for sub-millisecond p99, look at Rust.
- Heavy GUI / TUI / desktop work — Go's UI story is still weak. Rust + egui, C++ + Qt, or just write it in TypeScript.
- A polyglot SDK distributed to many language ecosystems — the ergonomics of Go's `cgo` boundary make it a poor source language for binding generation.
- A scripting-style one-off where startup time and developer iteration speed dominate — Python, Bash, or a single-file `uv run` script.

Go is great at: networked services, CLIs, infrastructure tooling, anything that benefits from a single static binary and a robust stdlib.

## Don't / Do

| Don't | Do |
|---|---|
| `interface{}` in new code | `any` |
| `for i := 0; i < 10; i++` for plain counting | `for i := range 10` (1.22+) |
| Hand-rolled `Contains`/`Sort`/`Index` over slices | `slices.Contains`, `slices.Sort`, `slices.Index` |
| `fmt.Println("debug:", x)` in libraries | `slog.Debug("describing thing", "x", x)` |
| `fmt.Errorf("...: %v", err)` when callers might inspect | `fmt.Errorf("...: %w", err)` |
| `errors.New(fmt.Sprintf(...))` | `fmt.Errorf(...)` |
| `err == ErrFoo` on a possibly-wrapped error | `errors.Is(err, ErrFoo)` |
| `err.(*MyErr)` on a possibly-wrapped error | `errors.As(err, &target)` (or `errors.AsType[*MyErr](err)` 1.26+) |
| `wg.Add(1); go func() { defer wg.Done(); … }()` (1.25+) | `wg.Go(func() { … })` |
| Naked `go fn()` with no context, no waitgroup | `errgroup.WithContext` or supervised by something that owns lifecycle |
| `sync.Once` + closed-over result | `sync.OnceValue(f)` (1.21+) |
| Store `context.Context` in a struct | Pass `ctx` as the first parameter |
| `time.After(d)` inside a `select` in a hot loop | `t := time.NewTimer(d); defer t.Stop()` and `Reset` |
| `http.Get(url)` / `http.DefaultClient` in production | `*http.Client{Timeout: …, Transport: …}` constructed once |
| `http.Server{Addr: …}` without timeouts | Set `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout` |
| `gin`/`fiber` on a new internal service | stdlib `net/http` with 1.22+ pattern routing, fall back to `chi` only when needed |
| `gorm` on a new service | `pgx/v5` + `sqlc` |
| `log.Printf` / package `log` for diagnostics | `log/slog` |
| `viper` without `cobra` | `caarlos0/env/v11` (or `koanf` for multi-source) |
| Define an `IThing` interface next to one implementation | Define the interface in the consumer that needs it |
| Embedded `sync.Mutex` on an exported struct | Unexported `mu sync.Mutex` field |
| `panic` for expected failure modes | return an error |
| Naked type assertion `x.(T)` outside "should panic" sites | `x, ok := v.(T); if !ok { … }` |
| `tools.go` blank imports | `go.mod` `tool` directive (1.24+) |
| `golang-standards/project-layout` `pkg/` | Public code at module root; private in `internal/` |
| `gofmt`-only on a 2026 project | `gofumpt` (superset, integrated into `gopls`) |
| `golangci-lint` v1 config | Migrate to v2 (`golangci-lint migrate`) |
| `_ = err` swallowing errors | Handle, log-and-continue with explicit comment, or return |
| `httpClient := &http.Client{}` per request | Construct once, share it (it's safe for concurrent use) |
| `go.mod` `go 1.21` on a new module | `go 1.25.0` (matches floor) |
| Build with `go build .` for a release | `goreleaser` v2 with `-trimpath`, `-ldflags`, `-buildvcs=true` |
| `alpine` base image | `gcr.io/distroless/static-debian12:nonroot` |
