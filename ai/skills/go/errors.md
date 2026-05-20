# Error Handling

Error handling in Go is settled. The Go team **officially closed all error-syntax proposals in June 2025** — no `try`, no `?`, no `check`/`handle`. The team's position: `if err != nil { return err }` is the permanent idiom, not a wart awaiting a fix. Combined with `errors.Is` / `errors.As` / `errors.Join` / `fmt.Errorf("%w")`, plus the 1.26 generic helper `errors.AsType`, this is the full picture for 2026.

The most common AI failure mode here is treating errors like exceptions — wrapping with `%v` so the chain is lost, type-asserting on wrapped errors, logging *and* returning the same error (double-reported), or ignoring with `_` outside of throwaway code. The second most common is sentinel-everywhere when a typed error would carry the structured fields callers actually need.

## The canonical pattern

```go
if err := db.Query(ctx, q); err != nil {
	return fmt.Errorf("query users by status %q: %w", status, err)
}
```

That single line is the entire pattern. Every word matters:

- **`fmt.Errorf`** — never `errors.New(fmt.Sprintf(...))`.
- **`%w`** — wraps the underlying error so callers can `Is`/`As` through it. `%v` flattens.
- **The wrap message says what *this* layer was doing.** "query users by status" — not "failed" or "error" or just "%w" alone. The caller's wrap message will say what *they* were doing. Together they form a breadcrumb trail.

A complete stack:

```
parse config: read config file: open /etc/svc/config.yaml: permission denied
```

Each layer adds one phrase. The leaf is the OS error. Reading top-to-bottom tells you what was happening and why.

## Inspecting errors

### `errors.Is` — for sentinel matching

```go
var ErrNotFound = errors.New("not found")

err := repo.GetUser(ctx, id)
if errors.Is(err, ErrNotFound) {
	return Response{Status: 404}
}
```

`errors.Is(err, target)` walks the wrapping chain looking for an error equal to (or matching, via `Is(error) bool` method) the target. Use for sentinel errors (`io.EOF`, `fs.ErrNotExist`, your own `ErrFoo`).

### `errors.As` — for typed-error extraction

```go
type ValidationError struct {
	Field, Msg string
}

func (v *ValidationError) Error() string { return v.Field + ": " + v.Msg }

err := svc.Create(ctx, input)
var ve *ValidationError
if errors.As(err, &ve) {
	return Response{Status: 400, Body: ve.Msg}
}
```

`errors.As(err, &target)` walks the chain, copying the first matching error into `target`. The target must be a non-nil pointer to a type implementing `error` (or pointer-to-pointer for `*Type`).

### `errors.AsType` — 1.26 generic helper

```go
var ve = errors.AsType[*ValidationError](err)
if ve != nil {
	return Response{Status: 400, Body: ve.Msg}
}
```

Avoids the `var target; errors.As(err, &target)` dance. Returns the matched value or the zero value. The non-generic `errors.As` is still legal and clearer in some contexts (e.g., chained `As` checks).

### `errors.Unwrap`

Rarely called directly — `Is` and `As` do the walking for you. Use when you need to manually peel one layer.

## Sentinel vs typed errors

| Kind | When | Example |
|---|---|---|
| **Sentinel** (`var ErrFoo = errors.New("foo")`) | Callers branch on *identity*. No structured fields needed. | `io.EOF`, `fs.ErrNotExist`, `sql.ErrNoRows`, your own `ErrNotFound`. |
| **Typed** (`type FooError struct{ Field string }`) | Callers need *structured data*. | `os.PathError`, `*net.OpError`, your own `*ValidationError`. |

Both can be wrapped (via `%w`) and inspected (`Is` / `As`). The choice is about what callers extract.

A typed error implements `Error() string` and may implement `Unwrap() error` (if it wraps a cause), and optionally `Is(target error) bool` (if its identity comparison is non-trivial):

```go
type NotFoundError struct {
	Resource string
	ID       string
}

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("%s %s not found", e.Resource, e.ID)
}

func (e *NotFoundError) Is(target error) bool {
	t, ok := target.(*NotFoundError)
	if !ok {
		return false
	}
	return e.Resource == t.Resource // identity by resource type, not ID
}
```

## Aggregating errors — `errors.Join`

```go
func validateUser(u User) error {
	var errs []error
	if u.Email == "" {
		errs = append(errs, errors.New("email required"))
	}
	if u.Age < 13 {
		errs = append(errs, errors.New("age must be ≥ 13"))
	}
	return errors.Join(errs...) // nil if errs is empty
}
```

`errors.Join(errs...)` returns a multi-error that's both `Is`-able and `As`-able for any of the joined errors. Its `Unwrap() []error` returns the constituent errors. Use for:

- **Validating N fields** and reporting all failures at once.
- **Closing N resources** in deferred cleanup, preserving all close errors.
- **Fan-out failures** where multiple goroutines might each return an error.

A handler typically prints the message; the joined error's default `Error()` returns each constituent's message on its own line.

## The deferred-close pattern

The canonical 2026 pattern for "open a resource, do work, close it, surface both errors":

```go
func processFile(path string) (err error) {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer func() { err = errors.Join(err, f.Close()) }()

	// ... do work, may return err
	return nil
}
```

Key points:

- **Named return** (`(err error)`) is required so the deferred function can mutate the return value.
- **`errors.Join`** preserves both the primary error and the close error. Plain `err = f.Close()` would overwrite a meaningful primary error with a (usually trivial) close error.
- **Only do this when the close error matters.** For a `*bytes.Buffer` it doesn't; for a database transaction, it does.

For HTTP responses, the analog:

```go
resp, err := client.Do(req)
if err != nil {
	return fmt.Errorf("send request: %w", err)
}
defer resp.Body.Close()

if resp.StatusCode >= 400 {
	return fmt.Errorf("server returned %d", resp.StatusCode)
}
```

(For `resp.Body`, `Close` errors usually don't matter; the `defer` is sufficient.)

## When NOT to wrap

Wrapping with `%w` is the default. Exceptions:

- **At trust boundaries** — translating an internal error to one suitable for an external API. Don't leak `pgx` errors through your HTTP response.
- **When the underlying error type is part of the API you don't want to expose.** A library might wrap as `%v` deliberately to keep its error type stable.
- **When the inner error is verbose noise** the caller can't act on. Wrap with `%v` (flatten) and surface a sentinel or typed error of your own.

```go
// Hide that we use pgx; expose our own typed error.
if errors.Is(err, pgx.ErrNoRows) {
	return User{}, ErrUserNotFound
}
```

This is **translation**, not loss — the caller gets an error they can match on.

## Panic vs error

- **`error`** for expected failure modes: file not found, parse error, timeout, validation failure.
- **`panic`** for unrecoverable programmer bugs: nil deref, impossible default case, broken invariant.

Library code returns errors. Library code calling another package's function should not let the inner package's panic escape — recover and convert to error if the call site is at a boundary.

### `recover` in middleware

The canonical HTTP middleware:

```go
func Recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			rv := recover()
			if rv == nil || rv == http.ErrAbortHandler {
				return
			}
			slog.ErrorContext(r.Context(), "panic in handler",
				"panic", rv,
				"stack", string(debug.Stack()),
			)
			w.WriteHeader(http.StatusInternalServerError)
		}()
		next.ServeHTTP(w, r)
	})
}
```

Notes:

- **`http.ErrAbortHandler`** is the stdlib's marker for "abort cleanly without a 500." Don't recover it.
- **Log the stack** — `debug.Stack()` captures the calling goroutine's stack at recovery time.
- **Don't `panic` again after recovering** — write the 500 and return.

For non-HTTP goroutines, wrap the entry-point function:

```go
go func() {
	defer func() {
		if r := recover(); r != nil {
			slog.Error("worker panic", "panic", r, "stack", string(debug.Stack()))
		}
	}()
	worker(ctx)
}()
```

## The "log and return" antipattern

```go
// WRONG
if err := svc.Do(); err != nil {
	slog.Error("Do failed", "err", err)
	return err
}
```

This logs once at the inner layer and again at the boundary that handles it. Pick one:

- **Log at the boundary** that decides how to respond (HTTP handler, CLI main, worker top-level).
- **Wrap and return** at every intermediate layer so the boundary log carries the full context chain.

The boundary log:

```go
if err := svc.Do(ctx, input); err != nil {
	slog.ErrorContext(ctx, "request failed",
		"err", err,
		"endpoint", "/v1/things",
	)
	writeError(w, err)
	return
}
```

## Status of `try` / `?` proposals

**Closed in June 2025.** The Go team's stated position is that `if err != nil` is the permanent idiom. Don't write code anticipating a future `try` — there isn't one. Don't import third-party "result type" libraries (`samber/lo` `Result[T]`, etc.) for new code; they read foreign and the wins are minor.

## Common idioms

### Predeclared errors at package scope

```go
package user

import "errors"

var (
	ErrNotFound      = errors.New("user not found")
	ErrAlreadyExists = errors.New("user already exists")
	ErrInvalidEmail  = errors.New("invalid email")
)
```

Export only what callers should match on. Keep internal failure modes private or convert to typed errors with structured fields.

### Wrap-once pattern

The common rookie mistake — wrapping the same error at every layer with redundant messages:

```go
// WRONG — every layer says "X failed"
return fmt.Errorf("getUser failed: %w", err)
return fmt.Errorf("handler failed: %w", err)
return fmt.Errorf("serve failed: %w", err)
// Result: "serve failed: handler failed: getUser failed: connection refused"
```

Each wrap should add **a phrase**, not a sentence, and ideally **a key parameter** (the ID, the path, the URL):

```go
return fmt.Errorf("get user %d: %w", id, err)
return fmt.Errorf("GET /users/%d: %w", id, err)
// Result: "GET /users/42: get user 42: connection refused"
```

If you have nothing to add, **don't wrap** — return `err` directly:

```go
return doThing(ctx, x) // no context to add, just propagate
```

### Errors as values

In some domains, errors are first-class data: a parser might return `[]ParseError` alongside a partial result. Use a struct return rather than `error`:

```go
type ParseResult struct {
	Tree   *Node
	Errors []ParseError
}
```

This is rare. The default is `(T, error)`.

### "Errors are inspected once"

Within a single chain of execution, an error should be inspected (Is/As) **at one place** — the boundary that decides what to do. Don't `Is`-check at every layer hoping to do something useful; let the error bubble up to the layer that *actually* knows the right response.

```go
// In the handler — the boundary that knows HTTP:
err := svc.GetUser(ctx, id)
switch {
case errors.Is(err, user.ErrNotFound):
	http.Error(w, "not found", 404)
case errors.Is(err, user.ErrUnauthorized):
	http.Error(w, "unauthorized", 401)
case err != nil:
	slog.ErrorContext(ctx, "get user", "err", err)
	http.Error(w, "internal error", 500)
default:
	writeJSON(w, user)
}
```

## Don't / Do

| Don't | Do |
|---|---|
| `errors.New(fmt.Sprintf(...))` | `fmt.Errorf(...)` |
| `fmt.Errorf("...: %v", err)` when callers might inspect | `fmt.Errorf("...: %w", err)` |
| `err == ErrFoo` on a possibly-wrapped error | `errors.Is(err, ErrFoo)` |
| `err.(*MyError)` on a possibly-wrapped error | `errors.As(err, &target)` (or `errors.AsType[*MyError](err)` in 1.26+) |
| `_ = svc.Do()` swallowing errors | Handle, log-and-continue with an explicit comment (`//nolint:errcheck // reason: …`), or return |
| Log error and also return it | Log at the boundary that decides response; wrap-and-return at intermediate layers |
| Wrap with `%w` and a vague message (`"failed: %w"`) | Add a *phrase* and a *key parameter* (`"get user %d: %w"`) |
| Use sentinel for something needing structured fields | Typed error (`type FooError struct{...}`) |
| Use typed error for pure identity matching | Sentinel (`var ErrFoo = errors.New(...)`) |
| `if err != nil { return errors.New(err.Error()) }` (unwrapping by string!) | `return err` or `return fmt.Errorf("context: %w", err)` |
| `panic` for expected failure modes (bad input, missing resource) | Return an error |
| Catch panics with `recover` everywhere "to be safe" | `recover` only at goroutine entry points and HTTP middleware |
| `errors.New` with `%s`-style formatting | `fmt.Errorf("%s: %w", x, err)` |
| Forget `defer` `cancel()` after `WithTimeout` | Always `defer cancel()` immediately |
| Discard close errors silently | `defer func() { err = errors.Join(err, f.Close()) }()` when close matters |
| Translate errors mid-chain unnecessarily | Wrap with `%w` at each layer; translate only at the API boundary |
| Compare errors with `strings.Contains(err.Error(), "...")` | Define a sentinel/typed error and use `errors.Is`/`As` |
| Import `samber/lo`'s `Result[T]` and friends | Stick with `(T, error)` — it's the Go idiom |
