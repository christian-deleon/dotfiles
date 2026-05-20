# Error Handling

Rust's error model is one of the language's strongest features: there are no exceptions, no surprise non-local returns, and the type system forces every fallible operation to be acknowledged in the signature. The standard idiom is `Result<T, E>` plus the `?` operator for propagation, with two crates filling out the gaps: **`thiserror`** for typed errors in libraries, **`anyhow`** for opaque errors with context in applications.

The most common AI failure mode here is `unwrap()` everywhere (panics in production), `Box<dyn std::error::Error>` as a public error type (loses all variant information), and hand-rolling error enums with manual `Display` and `From` impls when `thiserror` would generate them. All three are fixable mechanically.

## `Result<T, E>` and `Option<T>`

```rust
fn parse_port(s: &str) -> Result<u16, std::num::ParseIntError> {
    s.parse::<u16>()
}

fn first_word(s: &str) -> Option<&str> {
    s.split_whitespace().next()
}
```

Use `Option` when "absence" is a normal outcome with no failure reason. Use `Result` when there's a meaningful error type carrying information about what went wrong.

The two are related — `Option::ok_or` / `Option::ok_or_else` convert into `Result`:

```rust
let port: u16 = std::env::var("PORT")           // Result<String, VarError>
    .ok()                                        // Option<String>
    .and_then(|s| s.parse().ok())                // Option<u16>
    .ok_or("PORT missing or invalid")?;          // Result<u16, &str> via ?
```

## The `?` operator

`?` propagates errors. On a `Result`, it returns the `Err` early; on an `Option`, it returns `None` early:

```rust
fn read_port(path: &Path) -> Result<u16, MyError> {
    let text = std::fs::read_to_string(path)?;        // io::Error → MyError via From
    let port: u16 = text.trim().parse()?;             // ParseIntError → MyError via From
    Ok(port)
}
```

For `?` to work, the error you're propagating must convert to your function's error type via `From`. With `thiserror`'s `#[from]` attribute and `anyhow`'s blanket `From<E: std::error::Error>`, this conversion is usually free.

A `?` on `Option` requires the enclosing function to return `Option<_>` (or `Result<_, _>` with `?` after `.ok_or(...)`).

## `thiserror` — typed errors for libraries

`thiserror` (currently v2.x) generates `Display`, `Error`, and `From` impls from a `#[derive(Error)]`. Use it for libraries — callers benefit from being able to match on variants.

```rust
use std::path::PathBuf;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("config file not found: {path}")]
    NotFound { path: PathBuf },

    #[error("invalid TOML in {path}: {source}")]
    InvalidToml {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },

    #[error("io error reading {path}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("unexpected schema version {found}; expected {expected}")]
    BadVersion { found: u32, expected: u32 },
}
```

What this generates:

- `impl Display for ConfigError` using the `#[error("…")]` format strings.
- `impl std::error::Error for ConfigError` including `.source()` for the `#[source]` field.
- Optional `impl From<source-type> for ConfigError` when `#[from]` is used (see below).

### `#[from]` for automatic conversion

When you want bare `?` to convert without explicit code, use `#[from]`:

```rust
#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("io error")]
    Io(#[from] std::io::Error),

    #[error("invalid toml")]
    InvalidToml(#[from] toml::de::Error),
}

fn load(path: &Path) -> Result<Config, ConfigError> {
    let text = std::fs::read_to_string(path)?;     // io::Error → ConfigError::Io
    Ok(toml::from_str(&text)?)                      // toml::Error → ConfigError::InvalidToml
}
```

`#[from]` is great when the source error fully captures the context. When you need to attach more context (the path, the URL, the operation), use `#[source]` and convert manually:

```rust
fn load(path: &Path) -> Result<Config, ConfigError> {
    let text = std::fs::read_to_string(path)
        .map_err(|source| ConfigError::Io { path: path.to_path_buf(), source })?;
    toml::from_str(&text)
        .map_err(|source| ConfigError::InvalidToml { path: path.to_path_buf(), source })
}
```

Rule of thumb: `#[from]` for one-to-one variant-per-source-type errors with no extra context. Manual `map_err` when you want to attach fields.

### thiserror v2 notes

`thiserror` 2.0 (released Nov 2024) is the current major. Migration from v1 is mostly mechanical, but watch for:

- **Raw-identifier format args no longer accepted.** `#[error("type: {r#type}")]` → `#[error("type: {type}")]`.
- **Crates using `#[derive(Error)]` need `thiserror` as a *direct* dependency** (it's no longer pulled transitively from your derive macros). Add it explicitly with `cargo add thiserror`.
- **`#[from]`-derived fields no longer add an extra bound.** Slightly different inference; usually fine.
- **Disabling the `std` default feature gives no-std support** — the separate `thiserror-no-std` crate is dead.

### Hierarchy and layering

Big libraries typically have one root error type per layer of the public API:

```rust
#[derive(Debug, Error)]
pub enum DbError {
    #[error("connection failed")]
    Connect(#[source] sqlx::Error),
    #[error("query failed: {query}")]
    Query { query: String, #[source] source: sqlx::Error },
}

#[derive(Debug, Error)]
pub enum ApiError {
    #[error(transparent)]
    Db(#[from] DbError),
    #[error("unauthorized")]
    Unauthorized,
    #[error("validation: {0}")]
    Validation(String),
}
```

`#[error(transparent)]` forwards `Display` and `source()` to the wrapped type — useful when the wrapper exists for type purposes only and you don't want a layer of "DB error: " prefixing.

## `anyhow` — opaque errors with context for applications

In applications, you almost always just want "something went wrong, here's the chain of context, log it and exit." `anyhow::Error` is a single error type that boxes any `std::error::Error + Send + Sync + 'static`:

```rust
use anyhow::{Context, Result};
use std::path::Path;

fn run() -> Result<()> {
    let cfg = load_config(Path::new("config.toml"))
        .context("loading config")?;
    let port = open_port(&cfg)
        .with_context(|| format!("opening port {}", cfg.port))?;
    serve(port).context("serving requests")?;
    Ok(())
}
```

`anyhow::Result<T>` is `Result<T, anyhow::Error>`. The two methods that make `anyhow` worth using:

- `.context("static string")` — attaches a context message to an error.
- `.with_context(|| format!("..."))` — lazy form; the closure only runs on error.

When the error is printed (`{:#}` or `{:?}` debug), you get the full causal chain:

```text
Error: loading config

Caused by:
    0: io error reading config.toml
    1: No such file or directory (os error 2)
```

### When to reach for anyhow vs thiserror

| Situation | Pick |
|---|---|
| Library crate exposing errors to callers | `thiserror` — callers might match on variants |
| Binary / application | `anyhow` — no one matches on these, they get logged |
| Mixed crate (lib + bin in the same crate) | `thiserror` in the library part, `anyhow` in `main` and `bin/` |
| Internal helper functions in an app | `anyhow::Result<T>` everywhere, attach context with `.context(...)` |
| Public API function that returns a specific kind of error | Specific `thiserror` enum, even in an app crate |

Mixing freely is the norm — your library functions return `Result<T, MyLibError>`; your `main` builds on those with `anyhow` for ergonomic context propagation.

### Adding context

A common app pattern is to `?` everything and attach context at each layer:

```rust
fn load_user(db: &Pool, id: UserId) -> Result<User> {
    let row = db.fetch_one(id)
        .with_context(|| format!("fetching user {id}"))?;
    let user = User::try_from(row)
        .context("parsing user row")?;
    Ok(user)
}
```

The context messages stack up in the report, giving the operator a clear narrative of what was happening when it failed.

## `anyhow` vs `color-eyre` / `eyre`

`anyhow` is the default. `eyre` is API-compatible and pluggable — pair with `color-eyre` for prettier reports (colorized backtraces, span traces from `tracing-error`):

```toml
color-eyre = "0.6"
```

```rust
use color_eyre::Result;

fn main() -> Result<()> {
    color_eyre::install()?;
    // ...
    Ok(())
}
```

Pick `color-eyre` when the operator-facing output matters (CLI tools where humans read errors). Pick `anyhow` for everything else (services where errors go to structured logs).

## When `panic!` is correct

Panics are for **bugs** — invariant violations the type system can't express. They're not for expected failure modes.

| Use `panic!` (or `unwrap`/`expect`) when | Use `Result` when |
|---|---|
| The condition can't happen if the code is correct | The condition can plausibly happen at runtime |
| There's no sensible way to recover | The caller might want to retry / log / fall back |
| Unit tests / property tests asserting invariants | Production code paths that can fail under valid input |
| `expect("invariant: builder always sets host before build")` | I/O, parsing, config validation, anything depending on external state |

A panic in production code is **not** "we crashed gracefully" — it terminates the process (or the current thread, with `panic = "unwind"`). For a server, that's almost always wrong.

`expect("…")` is much better than `unwrap()` because it documents *why* the value should exist. Clippy has a lint (`unwrap_used`) you can enable to enforce this:

```toml
[lints.clippy]
unwrap_used = "warn"
expect_used = "allow"
```

### `panic = "abort"` vs `panic = "unwind"`

```toml
[profile.release]
panic = "abort"      # terminate immediately; smaller binary, no unwinding
```

Default is `"unwind"` — panics unwind the stack, running `Drop` impls. `"abort"` terminates immediately, which:

- Produces smaller binaries (no landing pads).
- Disables `catch_unwind` (you can't catch panics from another thread).
- Is what you want for most CLIs and many services.

`#[panic_handler]` for no-std environments is its own thing — read the embedded Rust documentation if you're there.

## Error patterns in async code

`?` works identically in async functions:

```rust
async fn fetch_user(client: &Client, id: UserId) -> Result<User> {
    let response = client.get(format!("/users/{id}"))
        .send()
        .await
        .context("sending request")?;
    let user = response
        .json::<User>()
        .await
        .context("parsing response")?;
    Ok(user)
}
```

The pitfall: when you have many concurrent tasks (`tokio::task::JoinSet`, `tokio::join!`), errors from different tasks can happen at the same time. See [async.md](async.md) for handling those — short version: `JoinSet::join_next` returns one result at a time, and you decide what "one task failed" means for the rest.

## Custom Display vs default

`thiserror` generates `Display` from `#[error("…")]`. If you want richer formatting, write `Display` by hand — `thiserror` still handles the `Error` trait and `From` conversions:

```rust
#[derive(Debug, Error)]
#[error("config error")]    // Display impl uses this
pub struct ConfigError {
    pub path: PathBuf,
    pub kind: ConfigErrorKind,
}

#[derive(Debug)]
pub enum ConfigErrorKind {
    NotFound,
    InvalidToml(toml::de::Error),
}
```

For most cases, the inline `#[error("...{field}...")]` format string is enough.

## Conversion via `From` — outside `thiserror`

When `#[from]` doesn't fit (e.g., you need to attach context during conversion), implement `From` by hand:

```rust
impl From<std::io::Error> for ConfigError {
    fn from(e: std::io::Error) -> Self {
        ConfigError::Io { path: PathBuf::new(), source: e }
    }
}
```

But honestly, when you have to attach context, the right answer is to `.map_err(|e| ...)` at the call site instead of via `From` — `From` should be the lossless one-to-one conversion.

## Reporting errors at the top of a binary

Two paths:

### `main() -> Result<()>` with anyhow

```rust
use anyhow::Result;

fn main() -> Result<()> {
    // ...
    Ok(())
}
```

When `main` returns `Err`, Rust prints `Error: {error:?}` and exits with non-zero. With anyhow, the `:?` formatting shows the full chain (`.context(...)` messages + sources).

### Explicit reporting

For nicer output (colors, structured info), report yourself:

```rust
fn main() {
    if let Err(e) = run() {
        eprintln!("error: {e:#}");
        for cause in e.chain().skip(1) {
            eprintln!("  caused by: {cause}");
        }
        std::process::exit(1);
    }
}
```

Or use `color-eyre`:

```rust
fn main() -> color_eyre::Result<()> {
    color_eyre::install()?;
    run()
}
```

## Common patterns

### Validate and parse together

```rust
pub struct EmailAddress(String);

impl EmailAddress {
    pub fn parse(raw: &str) -> Result<Self, ParseEmailError> {
        if !raw.contains('@') {
            return Err(ParseEmailError::MissingAt);
        }
        Ok(Self(raw.to_string()))
    }
}

#[derive(Debug, Error)]
pub enum ParseEmailError {
    #[error("email missing '@'")]
    MissingAt,
    #[error("local part too long")]
    LocalTooLong,
}
```

"Parse, don't validate" — return the validated type, not a `Result<bool>`.

### Iterator of `Result`s

`collect::<Result<Vec<_>, _>>()` short-circuits on the first error:

```rust
let nums: Result<Vec<u32>, _> = lines.iter().map(|s| s.parse::<u32>()).collect();
let nums = nums?;
```

If you want to keep going past errors, use `partition` or `filter_map`:

```rust
let (ok, errs): (Vec<u32>, Vec<_>) = lines.iter()
    .map(|s| s.parse::<u32>())
    .partition_map(|r| match r {
        Ok(v) => itertools::Either::Left(v),
        Err(e) => itertools::Either::Right(e),
    });
```

### Retries with backoff

For transient errors (network, rate limits), the `backon` crate is the modern idiomatic choice:

```rust
use backon::{ExponentialBuilder, Retryable};

let result = (|| async { fetch().await })
    .retry(ExponentialBuilder::default())
    .when(|e| matches!(e, MyError::Transient(_)))
    .await?;
```

For ad-hoc retries, just write the loop — don't reach for a crate for three iterations.

## Don't / Do

| Don't | Do |
|---|---|
| `Box<dyn std::error::Error>` as your public error type | `thiserror` enum (libs) or `anyhow::Error` (apps) |
| `unwrap()` in production | `expect("invariant: …")` with a real explanation, or proper `Result` flow |
| `.unwrap_or(default)` to hide bugs | Use it only when `default` is the deliberate fallback, not as panic-prevention |
| Manual `impl Display` / `impl Error` for every error type | `#[derive(thiserror::Error)]` with `#[error("…")]` |
| Hand-written `impl From<X> for MyError` for every variant | `#[from]` on `thiserror` variants |
| `panic!()` for expected runtime failures (bad input, missing file) | `Result` with a typed error |
| Catching panics with `catch_unwind` to recover | Fix the bug instead; or use `Result` from the start |
| Mixed anyhow inside a library's public API | anyhow only crosses the bin↔lib boundary in your own code; libraries expose typed errors |
| `#[error("…")]` with `{r#raw}` format args (broken in thiserror 2) | Use unraw identifiers in format strings |
| `.unwrap()` after a `match` to bypass exhaustiveness | Just match exhaustively |
| `Result<T, String>` for any non-trivial use | A real error type — `String` can't be matched, doesn't compose with `?` cleanly |
| Long `if let Err(_) = x { return Err(...) }` chains | `?` |
| Eagerly building expensive context strings | `.with_context(|| format!("..."))` — closure only runs on error |
| `lazy_static!` for an error registry | Just construct errors at the throw site; or `LazyLock<HashMap<...>>` if you really must cache |
