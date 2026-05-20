# Web Services & HTTP

The 2026 Go web stack is **stdlib-first**. Go 1.22's `net/http.ServeMux` pattern routing (`GET /items/{id}`) closed the gap with third-party routers, and the community has substantially moved off `gin`/`echo`/`gorilla` for new services. The canonical shape — Mat Ryer's "How I write HTTP services in Go" pattern, updated in 2024 — is a tiny `main()` delegating to a testable `run(ctx, args, stdout, stderr) error` plus a `NewServer(deps) http.Handler` constructor.

The most common AI failure mode here is reaching for `gin` because it's the most-starred (it carries reputational drag — inconsistent maintenance, custom `gin.Context` breaks `http.Handler` composition), wiring `http.DefaultClient` / `http.Get` (no timeout — production hangs forever), or using `gorm` on a greenfield service (the community has moved to `pgx` + `sqlc`). Other landmines: forgetting `http.Server.ReadHeaderTimeout` (Slowloris; `gosec` G112), `viper` without `cobra`, `log.Printf` instead of `slog`.

## The decision matrix

| Need | Pick | Notes |
|---|---|---|
| HTTP service | **stdlib `net/http`** | 1.22+ pattern routing; `chi` only if you need its middleware ecosystem |
| HTTP client | **stdlib `*http.Client`** | With explicit `Timeout` + tuned `Transport`; never `http.DefaultClient` |
| Retries | **`hashicorp/go-retryablehttp`** | Drop-in retrying client; `cenkalti/backoff/v4` for non-HTTP |
| Logging | **`log/slog`** | JSON in prod, text in dev; `otelslog` bridge for trace IDs |
| Config | **`caarlos0/env/v11`** | `koanf` for multi-source; `viper` only with `cobra` |
| DB (Postgres) | **`pgx/v5`** + **`sqlc`** | Avoid ORMs for greenfield |
| Migrations | **`pressly/goose`** | `ariga.io/atlas` for declarative schema |
| Tracing/metrics | **OpenTelemetry Go SDK** | `otelhttp`, `otelpgx`, `otelslog` |
| Background work | `errgroup` + goroutines | A real queue (Asynq, NATS, SQS) for durable async |

## The Mat Ryer pattern

The 2026 canonical service shape — every binary, every CLI:

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
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
	cfg, err := loadConfig()
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	logger := slog.New(slog.NewJSONHandler(stderr, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(logger)

	db, err := openDB(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}
	defer db.Close()

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           NewServer(logger, db, cfg),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       2 * time.Minute,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.InfoContext(ctx, "server starting", "addr", cfg.Addr)
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("server: %w", err)
		}
	case <-ctx.Done():
		logger.InfoContext(ctx, "shutdown initiated")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("shutdown: %w", err)
		}
	}
	return nil
}
```

Why this shape:

- **`run()` is testable.** Tests call `run(ctx, args, …)` directly; `main` is the boring shell.
- **`signal.NotifyContext`** ties signals to `ctx` — every downstream goroutine that watches `ctx.Done()` unwinds cleanly.
- **Bounded shutdown** — `WithTimeout(30s)` caps the time `Shutdown` will wait for in-flight requests.
- **`http.ErrServerClosed`** is the signal of "normal Shutdown completed" — don't treat it as a failure.

## Routing — stdlib `ServeMux` (1.22+)

```go
func NewServer(logger *slog.Logger, db DB, cfg Config) http.Handler {
	mux := http.NewServeMux()
	registerRoutes(mux, logger, db, cfg)
	var h http.Handler = mux
	h = LoggingMiddleware(logger)(h)
	h = Recoverer(logger)(h)
	h = otelhttp.NewHandler(h, "http-server")
	return h
}

func registerRoutes(mux *http.ServeMux, logger *slog.Logger, db DB, cfg Config) {
	mux.Handle("GET /health", handleHealth())
	mux.Handle("GET /v1/users/{id}", handleGetUser(db))
	mux.Handle("POST /v1/users", handleCreateUser(db))
	mux.Handle("DELETE /v1/users/{id}", handleDeleteUser(db))

	// 1.22+ patterns:
	// - Method prefix: "GET /…", "POST /…"
	// - Path wildcard: "/users/{id}" → r.PathValue("id")
	// - End anchor: "/foo/{$}" matches /foo exactly, not /foo/bar
	// - Host: "example.com/path"
}
```

Notes on 1.22+ patterns:

- **Method+path patterns**: `mux.Handle("GET /items/{id}", h)`. Without a method prefix, the pattern matches all methods (legacy behavior).
- **Wildcards**: `{id}` matches a single path segment; access via `r.PathValue("id")`. `{rest...}` matches everything to the end of the path.
- **`{$}` anchor**: `"/foo/{$}"` matches exactly `/foo` and `/foo/`, not `/foo/bar`.
- **Conflict resolution**: more-specific patterns win. `GET /users/{id}` beats `/users/{id}`.

When to reach for `chi`: middleware composition gets unwieldy (you want per-route middleware groups), or you need features stdlib doesn't have (URL params, route groups with prefix). `chi` is `http.Handler`-compatible — drop it in and out without rewriting handlers.

When **not** to reach for `gin`/`echo`/`fiber` on a new service: their `Context` types break stdlib middleware composition, the maintenance signal is inconsistent, and the 2026 community consensus has moved against them for greenfield.

## The handler "maker" pattern

Per-handler factories let you wire dependencies once and return an `http.Handler`:

```go
func handleGetUser(db DB) http.Handler {
	type response struct {
		ID    int    `json:"id"`
		Email string `json:"email"`
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		idStr := r.PathValue("id")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			http.Error(w, "invalid id", http.StatusBadRequest)
			return
		}

		u, err := db.GetUser(r.Context(), id)
		if errors.Is(err, ErrNotFound) {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		if err != nil {
			slog.ErrorContext(r.Context(), "get user", "err", err, "id", id)
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		writeJSON(w, response{ID: u.ID, Email: u.Email})
	})
}
```

Why factories:

- **Per-handler types** can be declared at handler-local scope (`type response struct {...}`).
- **Dependencies are explicit.** No reaching into globals.
- **Wiring runs once** at server construction; the returned `Handler` is ready to serve.

## Middleware

Plain `func(http.Handler) http.Handler`:

```go
func LoggingMiddleware(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			rw := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(rw, r)
			logger.InfoContext(r.Context(), "request",
				"method", r.Method,
				"path", r.URL.Path,
				"status", rw.status,
				"duration_ms", time.Since(start).Milliseconds(),
			)
		})
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(c int) {
	r.status = c
	r.ResponseWriter.WriteHeader(c)
}
```

Compose explicitly in `NewServer` (see top). `alice` exists but is unnecessary — listing middleware in order is clearer than dynamic registration.

## Recoverer middleware

```go
func Recoverer(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				rv := recover()
				if rv == nil || rv == http.ErrAbortHandler {
					return
				}
				logger.ErrorContext(r.Context(), "panic in handler",
					"panic", rv,
					"stack", string(debug.Stack()),
				)
				w.WriteHeader(http.StatusInternalServerError)
			}()
			next.ServeHTTP(w, r)
		})
	}
}
```

`http.ErrAbortHandler` is the stdlib's marker for "abort cleanly without a 500." Don't recover that one. The `chi/middleware/recoverer.go` source is the reference implementation worth reading.

## HTTP server timeouts (mandatory)

`gosec` G112 flags `http.Server{}` literals without `ReadHeaderTimeout`. **All four timeouts should be set** on any production server:

```go
&http.Server{
	Addr:              ":8080",
	Handler:           handler,
	ReadHeaderTimeout: 5 * time.Second,   // mandatory — defends against Slowloris
	ReadTimeout:       30 * time.Second,  // total time to read request body
	WriteTimeout:      30 * time.Second,  // total time to write response
	IdleTimeout:       2 * time.Minute,   // keep-alive max idle
}
```

Defaults are all zero ("no timeout") which is wrong for production.

## HTTP client — never `DefaultClient`

`http.DefaultClient` has no timeout. `http.Get(url)` uses it. In production, this means a slow or dead server can hang your request forever.

```go
client := &http.Client{
	Timeout: 30 * time.Second,
	Transport: &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 10, // matters when calling one backend a lot
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 5 * time.Second,
	},
}
```

`*http.Client` is safe for concurrent use. **Construct once, share** across the application.

For per-request finer control, use `context.WithTimeout` on the request context:

```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()

req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
resp, err := client.Do(req)
```

### Retries

`hashicorp/go-retryablehttp` is the drop-in for HTTP retries:

```go
import "github.com/hashicorp/go-retryablehttp"

rc := retryablehttp.NewClient()
rc.RetryMax = 4
rc.RetryWaitMin = 200 * time.Millisecond
rc.RetryWaitMax = 5 * time.Second
rc.Logger = slogAdapter(logger) // bring your own
client := rc.StandardClient() // wraps it as *http.Client
```

Always include **jitter** (which `retryablehttp` does by default) and **respect `Retry-After`** on 429 / 503 responses. For non-HTTP backoff, `cenkalti/backoff/v4` is the primitive.

## Logging — `log/slog`

The 2026 stdlib structured logger. Uncontested for new code.

### Init

```go
// run() — configure once
handler := slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
	Level: cfg.LogLevel, // slog.LevelDebug / Info / Warn / Error
})
logger := slog.New(handler)
slog.SetDefault(logger)
```

For dev:

```go
handler := slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelDebug})
```

### Logging

```go
logger.InfoContext(ctx, "user created", "user_id", u.ID, "email", u.Email)
logger.ErrorContext(ctx, "db query failed", "err", err, "query", "SELECT…")
```

Rules:

- **Always pass `ctx`** via `*Context` variants (`InfoContext`, `ErrorContext`, etc.) so trace/span IDs and request-scoped attributes are picked up.
- **Key-value pairs**, not `Printf` formatting. `slog.Info("x", "y", 1)` not `slog.Info(fmt.Sprintf("y=%d", 1))`.
- **Pre-bind common attributes** per request via middleware:
  ```go
  reqLogger := logger.With("request_id", reqID, "method", r.Method, "path", r.URL.Path)
  ctx := contextWithLogger(r.Context(), reqLogger)
  ```

### OpenTelemetry bridge

`go.opentelemetry.io/contrib/bridges/otelslog` auto-attaches trace IDs:

```go
import "go.opentelemetry.io/contrib/bridges/otelslog"

handler := otelslog.NewHandler("my-service",
	otelslog.WithLoggerProvider(global.GetLoggerProvider()),
)
slog.SetDefault(slog.New(handler))
```

Trace and span IDs flow into every log line automatically from the request context.

### When `zap`/`zerolog` still matter

Only when you've measured slog's JSON handler (~100 ns/op) as a hot-path cost. Both bench 4–5× faster, but the simplicity-and-stdlib win usually dominates. If you commit to `zerolog`, use its native API — the slog bridge is slower than the native one.

## Config — `caarlos0/env/v11`

Env-first, struct-based config with generics and modern API. Lightweight; ideal for services.

```go
import "github.com/caarlos0/env/v11"

type Config struct {
	Addr        string        `env:"ADDR"          envDefault:":8080"`
	LogLevel    slog.Level    `env:"LOG_LEVEL"     envDefault:"info"`
	DatabaseURL string        `env:"DATABASE_URL,required"`
	APIKey      Secret        `env:"API_KEY,required"`
	Timeout     time.Duration `env:"TIMEOUT"       envDefault:"30s"`
}

func loadConfig() (Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return cfg, fmt.Errorf("parse env: %w", err)
	}
	return cfg, nil
}
```

For multi-source (env + file + flag + vault), `koanf` is the recommended choice. **Avoid `viper`** unless you're already on `cobra` — heavy deps, surprising precedence.

### `Secret` type — redaction

Define a string-wrapper that refuses to print itself:

```go
type Secret string

func (Secret) String() string                { return "REDACTED" }
func (s Secret) MarshalJSON() ([]byte, error) { return []byte(`"REDACTED"`), nil }
func (s Secret) Reveal() string              { return string(s) }
```

Then `%v`-formatting a `Config` is safe to log. Reach for `.Reveal()` exactly at the point of use (e.g., constructing the SQL connection string).

### `.env` is for local dev only

Production secrets come from the orchestrator (Kubernetes Secrets, AWS Secrets Manager, Vault) injected as env vars. **Never commit `.env`** — ship `.env.example`.

## Database — `pgx/v5` + `sqlc`

The 2026 default for Postgres. Use the native `pgx` API (`*pgxpool.Pool`) rather than `database/sql` unless a library forces it.

### Connection pool

```go
import "github.com/jackc/pgx/v5/pgxpool"

func openDB(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse dsn: %w", err)
	}
	cfg.MaxConns = 25
	cfg.MaxConnLifetime = time.Hour       // play nice with PgBouncer / failover
	cfg.MaxConnIdleTime = 5 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("ping: %w", err)
	}
	return pool, nil
}
```

Pool sizing rule of thumb: `(num_app_instances * MaxConns) < postgres.max_connections - headroom`. For most services with a Postgres backend, `MaxConns=25` per instance is a reasonable default.

### `sqlc` — generated type-safe queries

`db/queries/users.sql`:

```sql
-- name: GetUser :one
SELECT id, email, created_at FROM users WHERE id = $1;

-- name: CreateUser :one
INSERT INTO users (email) VALUES ($1) RETURNING id, email, created_at;

-- name: DeleteUser :exec
DELETE FROM users WHERE id = $1;
```

`db/sqlc.yaml`:

```yaml
version: "2"
sql:
  - schema: "db/migrations"
    queries: "db/queries"
    engine: "postgresql"
    gen:
      go:
        package: "store"
        sql_package: "pgx/v5"
        out: "internal/store/postgres"
        emit_json_tags: true
        emit_db_tags: true
        emit_pointers_for_null_types: true
```

Run `sqlc generate` (or via `go tool sqlc generate` with the 1.24+ `tool` directive). The generator writes `queries.sql.go` with typed `Queries` methods:

```go
q := store.New(pool)
u, err := q.GetUser(ctx, id)
```

Why `pgx` + `sqlc` over ORMs:

- **SQL is the source of truth.** No second mental model.
- **Zero runtime reflection.** Generated code is plain Go.
- **Type-safe** without runtime panics on `nil` interface fields.
- **`pgx` is the fastest Postgres driver** and supports `LISTEN/NOTIFY`, COPY, pg-specific types.

GORM / ent only when the team is committed. `sqlx` is fine but development has slowed; `sqlc` is the active choice in 2026.

### Migrations — `pressly/goose`

`db/migrations/0001_init.up.sql`:

```sql
CREATE TABLE users (
    id         BIGSERIAL PRIMARY KEY,
    email      TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`db/migrations/0001_init.down.sql`:

```sql
DROP TABLE users;
```

Run:

```bash
goose -dir db/migrations postgres "$DATABASE_URL" up
goose -dir db/migrations postgres "$DATABASE_URL" status
goose -dir db/migrations postgres "$DATABASE_URL" create add_users_role sql
```

Embed migrations into the binary so deployment is one artifact:

```go
//go:embed db/migrations/*.sql
var migrationsFS embed.FS

func migrate(ctx context.Context, dsn string) error {
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return err
	}
	defer db.Close()

	goose.SetBaseFS(migrationsFS)
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	return goose.UpContext(ctx, db, "db/migrations")
}
```

For declarative schema (you describe the desired state, the tool produces the diff), `ariga.io/atlas` is the 2026 rising star. Many teams use Atlas to *generate* goose-compatible files.

## OpenTelemetry

```go
import (
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	"go.opentelemetry.io/otel/sdk/trace"
)

func setupTracing(ctx context.Context, cfg Config) (func(context.Context) error, error) {
	exp, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(cfg.OtlpEndpoint),
	)
	if err != nil {
		return nil, fmt.Errorf("otlp exporter: %w", err)
	}
	tp := trace.NewTracerProvider(
		trace.WithBatcher(exp),
		trace.WithResource(resource.NewSchemaless(
			attribute.String("service.name", cfg.ServiceName),
			attribute.String("service.version", version.Version),
		)),
	)
	otel.SetTracerProvider(tp)
	return tp.Shutdown, nil
}
```

Wrap handlers with `otelhttp.NewHandler` (server) and `otelhttp.NewTransport` (client). For `pgx`, the `otelpgx` package adds a `Tracer` to `pgxpool.Config`.

For metrics: `prometheus/client_golang` if you already have a Prom scraping setup; pure OTel metrics if you're greenfield. Both are valid in 2026.

## CLI

For distributed tools (users expect a familiar UX): **`spf13/cobra`** — same family as kubectl, gh, hugo, helm.

```go
import "github.com/spf13/cobra"

func newRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:   "my-svc",
		Short: "Manages widgets",
	}
	root.AddCommand(newServerCmd())
	root.AddCommand(newMigrateCmd())
	return root
}
```

For internal/personal tools (ergonomics over familiarity): **`alecthomas/kong`** — struct-tag driven, smaller, testable, no code generator:

```go
import "github.com/alecthomas/kong"

type CLI struct {
	Serve struct {
		Addr string `help:"listen address" default:":8080"`
	} `cmd:"" help:"Run the server"`

	Migrate struct {
		Up   struct{} `cmd:""`
		Down struct{} `cmd:""`
	} `cmd:""`
}

func run(ctx context.Context, args []string, stdout, stderr io.Writer) error {
	var cli CLI
	parser := kong.Must(&cli, kong.Name("my-svc"))
	kongCtx, err := parser.Parse(args[1:])
	if err != nil {
		return err
	}
	switch kongCtx.Command() {
	case "serve":
		return runServer(ctx, cli.Serve.Addr)
	case "migrate up":
		return migrateUp(ctx)
		// ...
	}
	return nil
}
```

For small scripts: stdlib `flag` is enough.

## Testing HTTP handlers

```go
import (
	"net/http/httptest"
)

func TestGetUser(t *testing.T) {
	t.Parallel()
	db := &fakeDB{users: map[int]User{42: {ID: 42, Email: "a@b.c"}}}
	h := handleGetUser(db)

	req := httptest.NewRequest("GET", "/v1/users/42", nil)
	req.SetPathValue("id", "42") // for tests bypassing the mux
	rr := httptest.NewRecorder()

	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rr.Code)
	}
	var body struct{ ID int }
	if err := json.NewDecoder(rr.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.ID != 42 {
		t.Errorf("id = %d, want 42", body.ID)
	}
}
```

For end-to-end (routing + middleware): test `run()` directly via `httptest.NewServer`, or call `NewServer(...)` and serve it through an `httptest.Server`.

For real database integration: `testcontainers-go` (see [tooling.md](tooling.md)).

## Common service mistakes

- **`http.DefaultClient` / `http.Get`** in production. Construct your own with `Timeout` + `Transport`.
- **`http.Server{}` literal without timeouts.** `ReadHeaderTimeout` is mandatory.
- **`r.Body` not closed.** Always `defer r.Body.Close()` after reading.
- **JSON decode without size limit.** `http.MaxBytesReader(w, r.Body, n)` to cap request size.
- **`log.Printf` / `fmt.Println` for diagnostics.** Use `log/slog`.
- **`os.Getenv("DATABASE_URL")` scattered through the code.** Centralize in `Config`; validate at startup.
- **`viper` without `cobra`.** Use `caarlos0/env/v11` or `koanf`.
- **`gorm` on a new service.** `pgx/v5` + `sqlc`.
- **`gin`/`echo`/`fiber` on a new service.** Start with stdlib `net/http`; fall back to `chi` if needed.
- **Not handling `http.ErrServerClosed`.** It's the success signal from `Shutdown`, not a failure.
- **`gin.Context` / `echo.Context`** APIs that don't compose with stdlib middleware. Stdlib `http.Handler` is the lingua franca.
- **Background work in `BackgroundTasks`-style "after the response."** Use a real queue for durability — Asynq (Redis), NATS, SQS.
- **Storing the request context** past the handler return. The context is canceled when the handler returns.
- **Not adding `signal.NotifyContext`** at the top of `main`/`run`. No graceful shutdown.
- **`sql.Open` without a `Ping` + bounded timeouts.** Failures show up much later than they should.
- **Reading the entire `r.Body` then re-using `r`.** It's already consumed; clone or `httputil.DumpRequest` first.
- **Allowing arbitrary URLs to a server-side fetcher** (SSRF). Validate and allowlist before sending.
