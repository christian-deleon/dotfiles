# Apps — CLIs, Web Services, and Cross-Cutting Concerns

This is the application-building reference. It assumes the rest of the stack — tokio runtime, anyhow errors, edition 2024 — is already in place (see the other reference files). The focus here is on the crates you'll actually wire together: `clap` for CLIs, `axum` for HTTP services, `reqwest` for HTTP clients, `tracing` for observability, `serde` for serialization, `figment` for config, and `sqlx` for databases.

## CLIs — `clap` (derive API)

`clap` is the default CLI framework in 2026. Use the derive API:

```toml
[dependencies]
clap = { version = "4", features = ["derive", "env"] }
clap_complete = "4"     # shell completions (optional)
```

### Basic shape

```rust
use clap::Parser;

/// Brief one-line tool description (becomes --help output)
#[derive(Debug, Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Path to the config file
    #[arg(short, long, default_value = "config.toml")]
    config: std::path::PathBuf,

    /// Increase verbosity (-v, -vv, -vvv)
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,

    /// Server URL
    #[arg(long, env = "SERVER_URL")]
    server: String,

    /// Names to process (positional)
    names: Vec<String>,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    tracing_subscriber::fmt()
        .with_max_level(match cli.verbose {
            0 => tracing::Level::WARN,
            1 => tracing::Level::INFO,
            2 => tracing::Level::DEBUG,
            _ => tracing::Level::TRACE,
        })
        .init();

    // ... use cli.config, cli.server, cli.names
    Ok(())
}
```

### Subcommands

```rust
#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    #[command(subcommand)]
    command: Command,

    /// Global flag — available on every subcommand
    #[arg(short, long, global = true)]
    verbose: bool,
}

#[derive(Debug, clap::Subcommand)]
enum Command {
    /// Start the server
    Serve {
        #[arg(long, default_value_t = 8080)]
        port: u16,
    },
    /// Run database migrations
    Migrate {
        #[arg(long)]
        up: bool,
    },
    /// Show config
    Config,
}

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Command::Serve { port } => { /* ... */ }
        Command::Migrate { up } => { /* ... */ }
        Command::Config => { /* ... */ }
    }
}
```

### Argument attributes — quick reference

| Attribute | What it does |
|---|---|
| `#[arg(short)]` | Adds a single-character flag (derived from field name) |
| `#[arg(short = 'p')]` | Explicit short flag |
| `#[arg(long)]` | Adds a long flag |
| `#[arg(long = "my-flag")]` | Explicit long flag (default is kebab-cased field name) |
| `#[arg(env = "ENV_VAR")]` | Fallback to env var if not on CLI |
| `#[arg(default_value = "val")]` | String default; parsed at runtime |
| `#[arg(default_value_t = 8080)]` | Typed default (more efficient) |
| `#[arg(required = true)]` | Force the flag |
| `#[arg(conflicts_with = "other")]` | Mutual exclusion |
| `#[arg(action = clap::ArgAction::Count)]` | `-vvv` → `3` |
| `#[arg(action = clap::ArgAction::SetTrue)]` | Bool flag without value |
| `#[arg(value_enum)]` | Parses into a `#[derive(ValueEnum)]` enum |
| `#[arg(value_parser = some_fn)]` | Custom parser |

### Custom value enums

```rust
#[derive(Debug, Clone, clap::ValueEnum)]
enum Format {
    Json,
    Yaml,
    Toml,
}

#[arg(long, value_enum, default_value_t = Format::Json)]
format: Format,
```

### Validation

Most validation belongs in `value_parser`:

```rust
fn validate_port(s: &str) -> Result<u16, String> {
    let port: u16 = s.parse().map_err(|_| "must be a number")?;
    if port < 1024 { Err("port must be >= 1024".into()) } else { Ok(port) }
}

#[arg(long, value_parser = validate_port)]
port: u16,
```

### Shell completions

```rust
use clap::CommandFactory;
use clap_complete::Shell;

#[derive(clap::Subcommand)]
enum Command {
    // ... real commands ...
    /// Generate shell completions
    Completions { #[arg(value_enum)] shell: Shell },
}

fn handle_completions(shell: Shell) {
    let mut cmd = Cli::command();
    clap_complete::generate(shell, &mut cmd, "myapp", &mut std::io::stdout());
}
```

## Web services — `axum`

`axum` is the default in 2026 — Tower-based, type-driven routes, and the tokio team's first-party HTTP framework.

```toml
[dependencies]
axum = "0.8"
tokio = { version = "1", features = ["full"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["trace", "compression-full", "cors"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
anyhow = "1"
thiserror = "2"
```

### Minimal server

```rust
use axum::{routing::get, Router, Json};
use serde::Serialize;

#[derive(Serialize)]
struct Health { status: &'static str }

async fn health() -> Json<Health> {
    Json(Health { status: "ok" })
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    let app = Router::new().route("/health", get(health));
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await?;
    tracing::info!("listening on {}", listener.local_addr()?);
    axum::serve(listener, app).await?;
    Ok(())
}
```

### Routes + Path + Query + Json extractors

```rust
use axum::{
    routing::{get, post},
    extract::{Path, Query, State},
    Router, Json,
};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct ListUsersQuery {
    #[serde(default)]
    limit: Option<u32>,
}

#[derive(Serialize, Deserialize)]
struct User { id: u64, name: String }

#[derive(Deserialize)]
struct CreateUser { name: String }

async fn list_users(
    State(db): State<AppState>,
    Query(q): Query<ListUsersQuery>,
) -> Result<Json<Vec<User>>, AppError> {
    let users = db.list_users(q.limit.unwrap_or(100)).await?;
    Ok(Json(users))
}

async fn get_user(
    State(db): State<AppState>,
    Path(id): Path<u64>,
) -> Result<Json<User>, AppError> {
    let user = db.get_user(id).await?.ok_or(AppError::NotFound)?;
    Ok(Json(user))
}

async fn create_user(
    State(db): State<AppState>,
    Json(body): Json<CreateUser>,
) -> Result<Json<User>, AppError> {
    let user = db.create_user(body.name).await?;
    Ok(Json(user))
}

fn app(state: AppState) -> Router {
    Router::new()
        .route("/users", get(list_users).post(create_user))
        .route("/users/:id", get(get_user))
        .with_state(state)
}
```

Extractors run in declaration order. The order matters: at most one body-consuming extractor per handler (`Json`, `Form`, `Bytes`, `String`), and it must come last. Path/Query/State/headers can be in any order before it.

### `State` — dependency injection

```rust
#[derive(Clone)]
struct AppState {
    db: Arc<sqlx::PgPool>,
    config: Arc<Config>,
}

let state = AppState { db: Arc::new(pool), config: Arc::new(cfg) };
let app = Router::new()
    .route("/users", get(list_users))
    .with_state(state);
```

`AppState` must be `Clone` and (for multi-threaded runtimes) `Send + Sync + 'static`. Wrapping the heavy bits in `Arc` keeps clones cheap.

For multiple states, either bundle them into one struct (above) or use multiple `Router::with_state` calls + sub-routers.

### Error handling — `IntoResponse` from a thiserror enum

The cleanest pattern: a typed error enum that implements `axum::response::IntoResponse`:

```rust
use axum::{http::StatusCode, response::{IntoResponse, Response}, Json};
use serde_json::json;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,
    #[error("unauthorized")]
    Unauthorized,
    #[error("validation: {0}")]
    Validation(String),
    #[error("database error")]
    Database(#[from] sqlx::Error),
    #[error("internal error")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, msg) = match &self {
            AppError::NotFound => (StatusCode::NOT_FOUND, "not found".to_string()),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized".to_string()),
            AppError::Validation(m) => (StatusCode::BAD_REQUEST, m.clone()),
            AppError::Database(e) => {
                tracing::error!(error = ?e, "database error");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".to_string())
            }
            AppError::Internal(e) => {
                tracing::error!(error = ?e, "internal error");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".to_string())
            }
        };
        (status, Json(json!({"error": msg}))).into_response()
    }
}
```

Now every handler can `?` against `AppError` and the response is well-typed.

### Middleware via Tower

`tower-http` provides ready-to-use middleware:

```rust
use tower_http::{
    trace::TraceLayer,
    compression::CompressionLayer,
    cors::CorsLayer,
    timeout::TimeoutLayer,
};
use std::time::Duration;

let app = Router::new()
    .route("/users", get(list_users))
    .layer(TraceLayer::new_for_http())                         // structured request logs
    .layer(CompressionLayer::new())                            // gzip/brotli
    .layer(CorsLayer::permissive())                            // CORS (lock down in prod)
    .layer(TimeoutLayer::new(Duration::from_secs(30)))         // request timeout
    .with_state(state);
```

Layer order is **outer-most first** (the layer applied last is the outermost wrapper). For middleware that needs to run before others (e.g., trace before timeout so the trace span captures the timeout), order them accordingly.

### Graceful shutdown

```rust
use tokio::signal;

async fn shutdown_signal() {
    let ctrl_c = async { signal::ctrl_c().await.expect("install ctrl_c handler"); };
    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("install SIGTERM handler")
            .recv()
            .await;
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    tracing::info!("shutdown signal received");
}

axum::serve(listener, app)
    .with_graceful_shutdown(shutdown_signal())
    .await?;
```

The server stops accepting new connections, finishes in-flight requests, then returns. For requests with long-lived state (background tasks, DB transactions), pair this with a `CancellationToken` (see [async.md](async.md)) that you signal alongside.

### Testing handlers

`axum` testing uses `tower::ServiceExt::oneshot` to call the router directly without a real HTTP listener:

```rust
use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

#[tokio::test]
async fn health_returns_ok() {
    let app = Router::new().route("/health", get(|| async { "ok" }));
    let response = app
        .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(&body[..], b"ok");
}
```

For integration tests with a real database, use `testcontainers` to spin up Postgres in Docker.

## HTTP client — `reqwest`

`reqwest` 0.13+ defaults to **rustls** (pure Rust, no OpenSSL/C toolchain). Add it with default features for almost every use case:

```toml
reqwest = { version = "0.13", features = ["json", "stream"] }
```

### Async client

```rust
let client = reqwest::Client::builder()
    .timeout(Duration::from_secs(30))
    .user_agent(concat!(env!("CARGO_PKG_NAME"), "/", env!("CARGO_PKG_VERSION")))
    .build()?;

let user: User = client
    .get("https://api.example.com/users/me")
    .bearer_auth(token)
    .send()
    .await?
    .error_for_status()?
    .json()
    .await?;

let response = client
    .post("https://api.example.com/users")
    .json(&NewUser { name: "alice".into() })
    .send()
    .await?
    .error_for_status()?;
```

`error_for_status()` converts 4xx/5xx responses into `Err`. Without it, a 500 is a "successful" response with a body — almost never what you want.

### Reusing the client

`reqwest::Client` is **cheap to clone** and internally pools connections. **Don't** create a new client per request:

```rust
// CORRECT — one Client, cloned where needed
#[derive(Clone)]
struct AppState {
    client: reqwest::Client,
    // ...
}

// WRONG — new client per request, connection pool churn
async fn handler() -> Result<...> {
    let client = reqwest::Client::new();   // bad — defeats connection pooling
    // ...
}
```

A common pattern is a global `LazyLock<Client>`:

```rust
use std::sync::LazyLock;
static HTTP: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .expect("build http client")
});
```

### Blocking client — for scripts only

For `rust-script` one-offs or sync code:

```toml
reqwest = { version = "0.13", features = ["blocking", "json"] }
```

```rust
let body = reqwest::blocking::get("https://example.com")?.text()?;
```

Never use `reqwest::blocking` from inside an async function — it spawns its own internal runtime and will deadlock.

### TLS — opting back into native-tls

The default `rustls` is the right choice. Use `native-tls` only when you specifically need the OS trust store (corporate certs on Windows/macOS):

```toml
reqwest = { version = "0.13", default-features = false, features = ["native-tls", "json"] }
```

## Logging and tracing — `tracing`

`tracing` is the modern observability framework — structured spans and events, async-aware. `log` is the older crate; new code should use `tracing` from the start.

```toml
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json", "fmt"] }
tracing-opentelemetry = "0.27"     # only if you're emitting to OTLP
opentelemetry = { version = "0.27", features = ["trace"] }     # likewise
```

### Initialize at startup

For development:

```rust
tracing_subscriber::fmt()
    .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
    .with_target(false)
    .compact()
    .init();
```

For production / JSON logs:

```rust
tracing_subscriber::fmt()
    .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
    .json()
    .with_current_span(true)
    .with_span_list(false)
    .init();
```

`RUST_LOG` controls the filter: `RUST_LOG=info,my_app=debug,sqlx=warn`.

### Emit events and spans

```rust
use tracing::{info, debug, warn, error, instrument};

#[instrument(skip(db), fields(user_id = %id))]
async fn load_user(db: &Pool, id: UserId) -> Result<User> {
    debug!("looking up user");
    let row = db.fetch_one(id).await?;
    info!("found user: {}", row.name);
    Ok(row.try_into()?)
}
```

What `#[instrument]` does:

- Wraps the function body in a `tracing::span!` with the function name.
- Adds named fields (`user_id = %id` here — `%` uses `Display`, `?` uses `Debug`).
- `skip(...)` omits arguments from the span (useful for large or sensitive params).
- Captures the function's return value if you add `ret`; the error if you add `err`.

### Structured fields

```rust
info!(user_id = %id, action = "login", "user logged in");
warn!(elapsed_ms = elapsed.as_millis(), "slow request");
error!(error = ?e, "request failed");
```

The structured fields show up as separate columns in JSON logs and as tags in OpenTelemetry — never glue them into the message text.

### `?` vs `%` field specifiers

- `field = value` — uses `Display` (or `Debug` for non-string-like types).
- `field = ?value` — explicit `Debug`.
- `field = %value` — explicit `Display`.

Prefer `%` for things that have a clean `Display` (IDs, URLs, durations) and `?` for complex structs.

### Distributed tracing

For OpenTelemetry export:

```rust
use opentelemetry::trace::TracerProvider;
use tracing_subscriber::prelude::*;

let provider = opentelemetry_sdk::trace::TracerProvider::builder()
    .with_simple_exporter(opentelemetry_stdout::SpanExporter::default())  // or OTLP exporter
    .build();
let tracer = provider.tracer("my-service");

tracing_subscriber::registry()
    .with(tracing_subscriber::fmt::layer())
    .with(tracing_opentelemetry::layer().with_tracer(tracer))
    .with(tracing_subscriber::EnvFilter::from_default_env())
    .init();
```

Spans created via `tracing` automatically propagate as OpenTelemetry spans. Pair with the OTLP exporter for production.

## Serialization — `serde`

`serde` is still dominant in 2026. The derive workflow:

```toml
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
serde_yaml_ng = "0.10"     # `serde_yaml` (the original) is unmaintained; this is the active fork
```

### Basic derive

```rust
use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize)]
struct User {
    id: u64,
    name: String,
    #[serde(rename = "emailAddress")]
    email: String,
    #[serde(default)]
    active: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    bio: Option<String>,
}
```

Common attributes:

| Attribute | What it does |
|---|---|
| `#[serde(rename = "x")]` | Field name in JSON differs from Rust |
| `#[serde(rename_all = "camelCase")]` (on container) | Convert all field names |
| `#[serde(default)]` | Missing → `Default::default()` |
| `#[serde(default = "fn_name")]` | Missing → call this function |
| `#[serde(skip)]` | Don't serialize/deserialize this field |
| `#[serde(skip_serializing_if = "fn")]` | Skip if predicate true |
| `#[serde(flatten)]` | Inline a nested struct into the parent |
| `#[serde(tag = "type")]` (on enum) | Tagged union JSON shape |
| `#[serde(transparent)]` (on newtype) | Serialize as the wrapped value |
| `#[serde(with = "module")]` | Custom serializer module (e.g., dates) |

### Enum representations

```rust
// Internally tagged: {"type": "login", "user": "alice"}
#[derive(Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Event {
    Login { user: String },
    Logout { user: String },
}

// Externally tagged (default): {"Login": {"user": "alice"}}

// Untagged: tries each variant until one parses
#[derive(Serialize, Deserialize)]
#[serde(untagged)]
enum Value {
    Int(i64),
    Str(String),
}
```

### Performance — when to reach for alternatives

For high-throughput services where serde becomes the bottleneck:

- **`rkyv`** — zero-copy deserialization. Real performance niche, growing adoption.
- **`postcard`** — serde-compatible compact binary format. Common for embedded and message queues.
- **`borsh`** — deterministic binary format (blockchain ecosystem).
- **`bincode`** — straightforward binary serde.

For 99% of services, plain `serde_json` is fast enough.

## Config — `figment` (or just serde + toml)

For non-trivial config (env vars + file + CLI overrides), `figment` is the modern recommendation:

```toml
figment = { version = "0.10", features = ["toml", "env"] }
serde = { version = "1", features = ["derive"] }
```

```rust
use figment::{Figment, providers::{Format, Toml, Env}};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Settings {
    pub database_url: String,
    pub port: u16,
    #[serde(default = "default_workers")]
    pub workers: usize,
    pub log_level: String,
}

fn default_workers() -> usize { 4 }

impl Settings {
    pub fn load() -> Result<Self, figment::Error> {
        Figment::new()
            .merge(Toml::file("config.toml"))
            .merge(Env::prefixed("APP_"))
            .extract()
    }
}
```

This layers `config.toml` (file), then `APP_*` env vars (overrides). Errors include where each value came from — invaluable when debugging.

For simple cases, plain `serde + toml::from_str` is fine:

```rust
let settings: Settings = toml::from_str(&std::fs::read_to_string("config.toml")?)?;
```

### Secrets

Never log secrets and never `Debug`-print them. Use a wrapper:

```rust
use secrecy::{Secret, ExposeSecret};

#[derive(Deserialize)]
struct Settings {
    database_url: Secret<String>,
}

// Use:
let conn = sqlx::connect(settings.database_url.expose_secret()).await?;
```

`secrecy::Secret<T>` redacts in `Debug` output. The `expose_secret()` method makes consumption explicit (and greppable in code review).

## Databases — `sqlx`

`sqlx` is the default async DB crate in 2026. Compile-time-checked SQL is the differentiator — `query!` macros run real queries against a real database at build time to verify column types.

```toml
sqlx = { version = "0.8", default-features = false, features = [
    "runtime-tokio",
    "tls-rustls",
    "postgres",                    # or "mysql", "sqlite"
    "uuid",
    "chrono",                      # or "time"; for jiff support check sqlx feature flags / community shims
    "macros",
    "migrate",
] }
```

### Connection pool

```rust
use sqlx::postgres::PgPoolOptions;

let pool = PgPoolOptions::new()
    .max_connections(20)
    .acquire_timeout(Duration::from_secs(3))
    .connect(&settings.database_url).await?;
```

Clone the pool freely — it's cheap and shares the underlying connection pool. Put it in your `AppState`.

### Querying

```rust
// query! — compile-time checked, returns a typed row
let user = sqlx::query!(
    "SELECT id, name, email FROM users WHERE id = $1",
    id
)
.fetch_one(&pool)
.await?;
println!("{} {}", user.id, user.name);

// query_as! — type-checks against a struct
#[derive(sqlx::FromRow)]
struct User { id: i64, name: String, email: String }

let user: User = sqlx::query_as!(
    User,
    "SELECT id, name, email FROM users WHERE id = $1",
    id
)
.fetch_one(&pool)
.await?;

// query() — dynamic / runtime-built, not checked
let row = sqlx::query("SELECT id, name FROM users WHERE id = $1")
    .bind(id)
    .fetch_one(&pool)
    .await?;
let id: i64 = row.try_get("id")?;
```

`query!` and `query_as!` need a live database at compile time, or a checked-in offline cache (`SQLX_OFFLINE=true` + `cargo sqlx prepare`). For CI, commit the `.sqlx/` cache.

### Transactions

```rust
let mut tx = pool.begin().await?;
sqlx::query!("INSERT INTO users (name) VALUES ($1)", name)
    .execute(&mut *tx).await?;
sqlx::query!("UPDATE counts SET total = total + 1")
    .execute(&mut *tx).await?;
tx.commit().await?;
```

Dropping the transaction without `.commit()` rolls back automatically.

### Migrations

```bash
cargo install sqlx-cli --locked
sqlx migrate add create_users
# edit migrations/<timestamp>_create_users.sql
sqlx migrate run
```

In code:

```rust
sqlx::migrate!("./migrations").run(&pool).await?;
```

Migrations run at startup, tracked in a `_sqlx_migrations` table.

### Alternatives

- **`sea-orm`** (2.0 released Jan 2026) — ActiveRecord-style ORM on top of sqlx. Use when you want entity models and a richer query DSL.
- **`diesel`** (2.3+) — sync (with `diesel-async` for async), the most mature option. Compile-time-checked DSL queries, schema generation from migrations. Pick when you value compile-time safety over async-first ergonomics.

## Putting it together — a small service

```rust
use axum::{routing::{get, post}, Router, Json, extract::{State, Path}, response::IntoResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use tower_http::trace::TraceLayer;
use tracing::instrument;

#[derive(Clone)]
struct AppState {
    db: PgPool,
    config: Arc<Settings>,
}

#[derive(Deserialize)]
struct Settings {
    database_url: String,
    port: u16,
}

#[derive(Serialize, sqlx::FromRow)]
struct User { id: i64, name: String, email: String }

#[derive(Deserialize)]
struct NewUser { name: String, email: String }

#[instrument(skip(state))]
async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> Result<Json<User>, AppError> {
    let user = sqlx::query_as!(User, "SELECT id, name, email FROM users WHERE id = $1", id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;
    Ok(Json(user))
}

#[instrument(skip(state))]
async fn create_user(
    State(state): State<AppState>,
    Json(body): Json<NewUser>,
) -> Result<Json<User>, AppError> {
    let user = sqlx::query_as!(
        User,
        "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email",
        body.name,
        body.email,
    )
    .fetch_one(&state.db)
    .await?;
    Ok(Json(user))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter("info").json().init();

    let settings: Settings = toml::from_str(&std::fs::read_to_string("config.toml")?)?;
    let db = sqlx::PgPool::connect(&settings.database_url).await?;
    sqlx::migrate!().run(&db).await?;

    let state = AppState { db, config: Arc::new(settings) };

    let app = Router::new()
        .route("/users/:id", get(get_user))
        .route("/users", post(create_user))
        .layer(TraceLayer::new_for_http())
        .with_state(state.clone());

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", state.config.port)).await?;
    tracing::info!(port = state.config.port, "listening");
    axum::serve(listener, app).with_graceful_shutdown(shutdown_signal()).await?;
    Ok(())
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}

#[derive(Debug, thiserror::Error)]
enum AppError {
    #[error("not found")] NotFound,
    #[error(transparent)] Db(#[from] sqlx::Error),
}
impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        use axum::http::StatusCode;
        match &self {
            AppError::NotFound => (StatusCode::NOT_FOUND, "not found").into_response(),
            AppError::Db(_) => (StatusCode::INTERNAL_SERVER_ERROR, "internal error").into_response(),
        }
    }
}
```

Every piece in this skeleton is the 2026 default: tokio runtime, axum router with State and structured errors, sqlx with compile-time-checked queries, tracing with JSON output, anyhow at the boundary, thiserror for HTTP errors, graceful shutdown wired up.

## Anti-patterns

| Don't | Do |
|---|---|
| `println!`/`eprintln!` for logging | `tracing::info!`/`error!` with structured fields |
| One `reqwest::Client` per request | One shared `Client`; clone it (cheap), put in `AppState` |
| `axum` handler that calls `unwrap()` on a `Result` | Return a typed error implementing `IntoResponse` |
| `Box<dyn Error>` as the error type in a handler signature | thiserror enum + `IntoResponse` |
| Building config from `std::env::var` calls scattered through code | One typed `Settings` struct loaded via figment or serde+toml |
| Hardcoded secrets in source | `secrecy::Secret<String>` + env/config; never log them |
| Logging `request.body()` or full request payloads | Log a fingerprint or sanitized summary; bodies leak PII |
| `query("SELECT ... WHERE id = '" + id + "'")` | `query!("SELECT ... WHERE id = $1", id)` — compile-checked AND injection-safe |
| `sqlx::PgPool::connect` per request | Connect once at startup, share via `AppState`, clone cheaply |
| `sleep(retry_delay)` polling loops for transient errors | `backon` crate, or use the underlying library's built-in retry |
| Spawning a background task without graceful shutdown wiring | `CancellationToken` + `JoinSet` so shutdown stops them cleanly |
| Forgetting `error_for_status()` after `reqwest::send()` | Always call it (or check `.status()` explicitly) — a 500 isn't a transport error |
| Logging unredacted error chains containing connection strings | Wrap secrets in `Secret<T>`; sanitize before logging |
| One global `Mutex<DbPool>` | `PgPool` is internally synchronized; just clone it |
| `clap` `parse_from(std::env::args())` in tests | `Cli::try_parse_from(["bin", "--flag", "val"])` for unit testing CLI parsing |
| `tracing_subscriber::fmt::init()` called multiple times | Init once in `main`; tests can use `#[tracing_test::traced_test]` per test |
| `axum::Server::bind(...)` (old API) | `axum::serve(listener, app)` (current API since 0.7) |
