# Concurrency

Go's concurrency primitives — goroutines, channels, `context.Context`, the `sync` package, `golang.org/x/sync/errgroup` — are mature and small. The 2026 baseline is "no naked goroutines": every concurrent function runs inside an `errgroup.Group`, a `sync.WaitGroup` (preferably via the 1.25+ `WaitGroup.Go` method), or a supervisor goroutine that explicitly watches `ctx.Done()`. The race detector (`go test -race`) is non-negotiable in CI. `testing/synctest` (stable in 1.25) makes time-dependent tests deterministic.

The most common AI failure mode here is naked `go fn()` with no lifecycle owner — guaranteed leak on shutdown. Close seconds: storing `context.Context` in a struct, `time.After` in a hot select loop (the leak is *fixed* in 1.23 but a `NewTimer` is still better for performance), `wg.Add(1)` inside the goroutine (races with `Wait`), and channels-as-state instead of `sync.Mutex` when the goal is shared mutation.

## The four rules

1. **Every goroutine has an owner.** The owner waits on completion or knows that the goroutine listens to `ctx.Done()` and stops on its own.
2. **`context.Context` is the first parameter** of every function that blocks or does I/O. Never stored in a struct.
3. **Every `WithCancel`/`WithTimeout`/`WithDeadline` is followed by `defer cancel()`.** No exceptions.
4. **`go test -race`** is part of every CI run.

Everything below is application of these rules.

## `errgroup` — the default fan-out primitive

`errgroup.Group` (`golang.org/x/sync/errgroup`) is the 2026 canonical primitive for "do N things concurrently, fail fast on the first error, propagate context cancellation."

```go
import "golang.org/x/sync/errgroup"

g, ctx := errgroup.WithContext(ctx)
g.SetLimit(8) // bounded concurrency (1.20+)

for _, item := range items {
	item := item // unnecessary in 1.22+; harmless. Drop in new code.
	g.Go(func() error {
		return process(ctx, item) // ctx is canceled when any sibling fails
	})
}

if err := g.Wait(); err != nil {
	return fmt.Errorf("processing items: %w", err)
}
```

Why this is the default:

- **`errgroup.WithContext`** ties the group's lifecycle to a derived context. Any goroutine returning a non-nil error cancels `ctx`, signaling siblings to stop.
- **`SetLimit(n)`** caps concurrency without a separate semaphore. `g.Go` blocks when `n` goroutines are already running.
- **`Wait()`** blocks until all goroutines return; surfaces the first non-nil error.

Don't share `ctx` from `errgroup.WithContext` after `Wait()` returns — it's canceled.

## `sync.WaitGroup.Go` (1.25+) — for non-erroring goroutines

For fan-out where each goroutine handles its own errors (or genuinely can't fail):

```go
var wg sync.WaitGroup
for _, item := range items {
	item := item
	wg.Go(func() {
		_ = handle(ctx, item)
	})
}
wg.Wait()
```

`WaitGroup.Go` (added in 1.25) eliminates the entire class of "`Add(1)` race with `Wait`" bugs. The old form is still legal but should not appear in new code:

```go
// Old form — don't write this anymore
var wg sync.WaitGroup
for _, item := range items {
	wg.Add(1)
	go func() {
		defer wg.Done()
		handle(ctx, item)
	}()
}
wg.Wait()
```

If you must use the old form (supporting <1.25), **always `Add` before `go`**. Adding inside the goroutine races with `Wait` returning early.

## `context.Context`

### The rules, restated

- **First parameter, named `ctx`.** Public API or private function — same rule.
- **Never stored in a struct.** Pass it through every call.
- **Never `nil`** — use `context.Background()` (top-level), `context.TODO()` (placeholder during refactor), or `r.Context()` (HTTP handler).
- **Always `defer cancel()`** after `WithCancel` / `WithTimeout` / `WithDeadline`. The contexts hold resources; not canceling leaks them until the parent context is canceled.

### Timeouts

```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()

resp, err := client.Do(req.WithContext(ctx))
```

### Cancellation with cause (1.20+)

`context.WithCancelCause` lets you record *why* a context was canceled, distinguishing user-initiated cancel from timeout from upstream failure:

```go
ctx, cancel := context.WithCancelCause(ctx)
defer cancel(errors.New("normal shutdown"))

// elsewhere:
cancel(fmt.Errorf("upstream service unhealthy: %w", err))

// check:
if err := context.Cause(ctx); err != nil {
	slog.ErrorContext(ctx, "operation canceled", "cause", err)
}
```

`context.Cause(ctx)` returns the cause if the context was canceled with one; otherwise the standard `context.Canceled` / `context.DeadlineExceeded`. Use when you need to distinguish "user pressed Ctrl+C" from "request timed out" from "upstream returned 503."

### `context.Value` — sparingly

```go
ctx = context.WithValue(ctx, traceIDKey{}, "abc-123")
```

Rules:

- **Key is an unexported type** (`type traceIDKey struct{}` or `type ctxKey int`), not a `string`. String keys collide.
- **Use only for request-scoped metadata** — trace IDs, request IDs, user identity. Not for dependencies (pass those explicitly).
- **Don't pass logger or DB handles via context.** Constructor injection or function parameter.

## Channels vs mutexes

The Rob Pike maxim "share memory by communicating" was once interpreted as "always use channels." The 2026 framing (Dave Cheney, post-Pike consensus):

> **Channels orchestrate ownership transfer and signaling. Mutexes protect short critical sections over shared state.**

Use **channels** when:

- You're moving ownership of a value between goroutines (producer→consumer pipeline).
- You're signaling readiness, completion, or shutdown (a `chan struct{}` or `ctx.Done()`).
- You need fan-in / fan-out / select-based dispatch.

Use **mutexes** when:

- You have shared state and the critical sections are short (cache, counter, registry).
- You need read-write parallelism (`sync.RWMutex`).
- A channel-based version would just be a complicated lock.

A counter with a mutex is **right**:

```go
type Counter struct {
	mu    sync.Mutex
	count int
}

func (c *Counter) Inc() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.count++
}
```

A counter with a channel is wrong — channels are for communication, not for serializing access to a single integer.

## `sync` primitives

### `sync.Mutex` / `sync.RWMutex`

```go
type Cache struct {
	mu    sync.RWMutex
	items map[string]item
}

func (c *Cache) Get(key string) (item, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	v, ok := c.items[key]
	return v, ok
}

func (c *Cache) Set(key string, v item) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.items[key] = v
}
```

Rules:

- **Unexported `mu` field.** Callers can't lock you out.
- **Don't embed in an exported struct.** Callers can copy → broken lock. `go vet copylocks` catches this.
- **`defer Unlock()` immediately after `Lock()`.** Always.
- **RWMutex** only when you've measured contention. The overhead is real; for short critical sections, plain `Mutex` is often faster.

### `sync.Once`, `sync.OnceFunc`, `sync.OnceValue`, `sync.OnceValues` (1.21+)

Prefer the typed helpers over bare `sync.Once`:

```go
// 1.21+ — preferred
var loadConfig = sync.OnceValue(func() Config {
	return mustLoad()
})

cfg := loadConfig() // computes once, returns cached
```

```go
// Equivalent old style — don't write in new code
var (
	once   sync.Once
	cfg    Config
)
func getConfig() Config {
	once.Do(func() { cfg = mustLoad() })
	return cfg
}
```

`OnceFunc(f)` for a side-effecting `func()`; `OnceValue(f)` for `func() T`; `OnceValues(f)` for `func() (T, U)`.

**Gotcha**: if the inner function panics, the `OnceFunc`/`OnceValue` helpers re-panic on every subsequent call (the bare `sync.Once` only panics once). This is usually what you want — a config load that panics is broken state, and you should fail loudly on every access.

### `sync.Pool`

For per-goroutine scratch buffers. Don't reach for it until you've measured allocation pressure:

```go
var bufPool = sync.Pool{
	New: func() any { return new(bytes.Buffer) },
}

func format(x Thing) string {
	buf := bufPool.Get().(*bytes.Buffer)
	defer func() {
		buf.Reset()
		bufPool.Put(buf)
	}()
	// ...
	return buf.String()
}
```

`sync.Pool` is not a cache — entries can be GC'd at any time. Use for short-lived per-call buffers, not for "hold N expensive objects."

### `sync/atomic`

For lock-free counters and flags. Use `atomic.Int64`, `atomic.Bool`, `atomic.Pointer[T]` (the typed forms, 1.19+) over the legacy free functions:

```go
var requests atomic.Int64

requests.Add(1)
n := requests.Load()
```

The legacy form `atomic.AddInt64(&i, 1)` requires careful alignment on 32-bit systems and is one of the easier APIs to mis-use. The typed forms eliminate the foot-guns.

## Channels — patterns

### Signaling done

```go
done := make(chan struct{})
go func() {
	defer close(done)
	// work
}()
// elsewhere:
<-done
```

`close(done)` lets every reader unblock simultaneously. Use `chan struct{}` (zero-sized) when no value matters.

### Fan-out / fan-in

```go
// Fan-out
jobs := make(chan Job)
results := make(chan Result)
for i := 0; i < runtime.NumCPU(); i++ {
	go func() {
		for j := range jobs {
			results <- process(j)
		}
	}()
}

// Fan-in
go func() {
	defer close(results) // signal consumers we're done
	// ... feed jobs, then close(jobs)
}()
```

**Closing rules:**

- **Only the sender closes a channel.** Closing from the receive side, or closing twice, panics.
- **Don't close a channel if multiple senders write to it** without coordination — they may panic on send. Use a separate `done` channel to signal "stop sending."
- **Closing is a broadcast** — every blocked receiver sees the zero value with `ok == false`.

### `select` for timeout / cancellation

```go
select {
case res := <-resultCh:
	return res, nil
case <-ctx.Done():
	return Result{}, ctx.Err()
}
```

Always include `ctx.Done()` in any blocking `select`. A `select` without a cancel arm is a leak waiting to happen.

### Avoid `time.After` in hot loops

`time.After` is **safe in 1.23+** (the timer leak is fixed), but it still allocates a new timer per call and lets the runtime collect it lazily. For tight loops, use `time.NewTimer` + `Reset`:

```go
t := time.NewTimer(d)
defer t.Stop()
for {
	select {
	case <-t.C:
		// work
		t.Reset(d)
	case <-ctx.Done():
		return ctx.Err()
	}
}
```

For one-shot in a non-hot path, `time.After` is fine.

## `testing/synctest` (1.25+ stable)

Deterministic testing for code that uses `time` and concurrency:

```go
import "testing/synctest"

func TestRetryBackoff(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		start := time.Now()

		client := NewClient(WithBackoff(time.Second))
		_ = client.Do(ctx, "fail-3-times")

		// Three retries with 1s, 2s, 4s — real elapsed: ~0ms.
		// Virtual elapsed: 7s.
		if got := time.Since(start); got != 7*time.Second {
			t.Errorf("elapsed = %v, want 7s", got)
		}
	})
}
```

Inside `synctest.Test`:

- **`time.Sleep`, `time.After`, `time.NewTimer`** are all virtualized.
- **The clock advances** only when every goroutine in the bubble is blocked.
- **Real `time.Now()`** is the virtualized clock.

Use it for any test that previously had `time.Sleep` in it to "wait for the async thing." `synctest.Wait(t)` blocks until all goroutines in the bubble are durably blocked — equivalent to "all the asynchronous work has caught up."

The experimental `GOEXPERIMENT=synctest` API from 1.24 was removed in 1.26; the stable API is what you write going forward.

## Goroutine leak detection — `uber-go/goleak`

```go
import "go.uber.org/goleak"

func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m)
}
```

Runs at the end of every test in the package and fails the run if any goroutine survives. Catches:

- Forgotten `defer cancel()`.
- Hung channel sends/receives.
- Workers that don't stop on `ctx.Done()`.

The 1.26 toolchain ships an in-runtime goroutine-leak profile (`GOEXPERIMENT=goroutineleakprofile`), but `goleak` remains the test-time tool.

## Race detector

`go test -race` enables the runtime race detector. It catches data races — concurrent access to shared memory where at least one access is a write, without synchronization. Costs ~2× CPU and ~5× memory; mandatory in CI.

Common races:

```go
// Race: m is shared, no lock
var m = make(map[string]int)
go func() { m["a"] = 1 }()
go func() { _ = m["a"] }()
```

```go
// Race: closure captures i
for i := 0; i < 10; i++ {
	go func() { fmt.Println(i) }()
}
// Fixed in 1.22+ by per-iteration loop variable. In <1.22: `i := i` before the goroutine.
```

```go
// Race: WaitGroup is fine, but ctx is shared without consideration
var wg sync.WaitGroup
wg.Go(func() { someState++ }) // race on someState
wg.Wait()
```

Some races are caught by `go vet`'s `copylocks` and `loopclosure` checks at compile time. The race detector catches the rest at runtime.

## Worker pools

For most fan-out, **`errgroup.WithContext` + `SetLimit`** is sufficient. Reach for a library only when:

- You have **long-lived workers** receiving from a queue.
- You need **priority levels** or **rate limiting** beyond a simple semaphore.
- You measured `errgroup` overhead and need lower allocation.

Libraries:

- **`sourcegraph/conc`** — structured concurrency primitives with strong type safety. Less code than `errgroup` for typed work.
- **`alitto/pond`** — high-throughput long-lived worker pools.

Both are fine; neither is required. `errgroup` covers ~90% of cases.

## Common anti-patterns

- **`go fn()` with no lifecycle owner.** Either wrap in `errgroup.Go`, use `WaitGroup.Go`, or pass a context whose cancellation `fn` must observe.
- **`wg.Add(1)` inside the goroutine.** Races with `Wait`. Add before `go`, or use `WaitGroup.Go` (1.25+).
- **Storing `context.Context` in a struct field.** Pass as the first parameter, every call.
- **`context.WithTimeout` without `defer cancel()`.** Leaks until the parent context is canceled.
- **Channel as a lock around a single int.** Use `sync.Mutex` or `atomic.Int64`.
- **Closing a channel multiple times** (or from the receive side). Panic.
- **`select { case x := <-ch: ... }`** with no `ctx.Done()` arm. Guaranteed leak path.
- **`time.After(d)`** in a hot select loop — still functional in 1.23+ but allocates per call. Use `time.NewTimer` + `Reset`.
- **Mutating shared state without sync.** The race detector catches it; CI should be running `-race`.
- **Copying a `sync.Mutex`/`WaitGroup`.** `go vet copylocks` catches this.
- **Passing dependencies via `context.WithValue`.** Inject them explicitly.
- **`select` with a `default` clause expecting it to "wait a bit then move on"** — `default` makes the select non-blocking. To wait with a timeout, use a `time.After` or `ctx.Done()` arm.
- **Channels as collection iteration.** Use `iter.Seq[T]` (1.23+) for lazy iteration; reserve channels for cross-goroutine communication.
- **Recovering panics globally "to be safe."** Recover at well-defined boundaries (HTTP middleware, goroutine entry points) and log+escalate. Catching everywhere hides real bugs.
- **Forgetting to drain a channel** when the writer is still running. Reader exit → blocked writer → leaked goroutine.
- **`runtime.Gosched()`** to "let other goroutines run." Almost always wrong — the runtime schedules fine on its own. The exception is tight loops with no preemption point, and even then a different design is usually right.
