---
name: rust
description: Modern Rust (edition 2024) for CLIs, services, and libraries — idioms, packaging, async, errors, web, testing. Use when editing `*.rs`/`Cargo.toml`, or for prompts about cargo, clippy, tokio, axum, reqwest, clap, serde, sqlx, thiserror, anyhow, tracing. Stack: clippy + rustfmt, cargo-nextest, tokio, axum, clap (derive), tracing.
compatibility: opencode
---

# Rust

Rust is a systems language that earns its keep on three axes: **memory safety without a GC** (the borrow checker enforces ownership statically), **zero-cost abstractions** (traits, generics, and iterators compile down to what you would have hand-written), and **fearless concurrency** (the type system rejects data races at compile time). The trade is a slow ramp — the compiler is strict, and "fight the borrow checker" is a real phase. Once you internalize ownership, you stop fighting and start designing data flow that the compiler accepts on the first try.

The most common AI failure mode here is writing 2018-era Rust: `unwrap()` everywhere, `Box<dyn Error>` as the error type for everything, blocking calls inside async functions, hand-rolled error enums without `thiserror`, `Arc<Mutex<T>>` reflexively reached for, cloning `String` to dodge the borrow checker, and `cargo test` ignored in favor of `println!` debugging. Don't do any of that. The defaults below assume edition 2024 on a recent stable toolchain.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Set up a project, manage toolchains, configure clippy/rustfmt, run tests | [tooling.md](tooling.md) |
| Author `Cargo.toml`, set up a workspace, pick features, ship a binary or library | [packaging.md](packaging.md) |
| Wrangle ownership, lifetimes, traits, generics, trait objects, smart pointers | [types.md](types.md) |
| Design error types, use `?`, pick between `thiserror` and `anyhow` | [errors.md](errors.md) |
| Write `async` code, structure concurrent tasks, pick between async/threads/rayon | [async.md](async.md) |
| Build a CLI or web service — axum, reqwest, clap, tracing, serde, sqlx | [apps.md](apps.md) |
| Containerize as a distroless image — cargo cache mounts, cross-compile, multi-arch, signing | [packaging.md](packaging.md) → "Containers" section. Universal Dockerfile/Compose/build/supply-chain patterns live in the [`docker`](../docker/SKILL.md) skill |

For one-off edits, the cheat sheets below are usually enough. Reach for the reference files when the task warrants depth.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Edition | **2024** | 1.85+ (Feb 2025). New crates start here; older crates upgrade with `cargo fix --edition`. Edition 2027 is in the pipeline but not yet stable |
| Toolchain | **stable** via `rustup` (1.95+ as of May 2026) | Pin per-project with `rust-toolchain.toml`; only reach for nightly when a specific feature requires it |
| Build / deps | **`cargo`** | One tool for build, test, run, doc, publish; no alternatives needed |
| Lint | **`cargo clippy`** | Treat warnings as errors in CI; `clippy::pedantic` is opt-in, `clippy::all` is the baseline |
| Format | **`cargo fmt`** | Default style; one knob (`edition`) in `rustfmt.toml`. No bikeshedding |
| Test runner | **`cargo nextest`** | Faster, better failure summaries, real parallel isolation; `cargo test` only when nextest isn't installed |
| Error types — libraries | **`thiserror`** | `#[derive(Error)]` enums; expose typed errors to callers |
| Error types — applications | **`anyhow`** | `anyhow::Result<T>` + `.context(...)`; opaque error type with backtraces |
| Async runtime | **`tokio`** (full features in apps, narrow features in libs) | Default for the ecosystem; `async-std` and `smol` exist but tokio is what axum/reqwest/sqlx all use |
| HTTP server | **`axum`** | Tower-based, routes + extractors + State; pairs naturally with tokio |
| HTTP client | **`reqwest`** | Built on `hyper`, async by default, sync feature flag for scripts |
| CLI | **`clap` (derive)** | `#[derive(Parser)]`; `clap_complete` for shell completions |
| Logging / tracing | **`tracing` + `tracing-subscriber`** | Structured spans + events; replaces `log` for any nontrivial app |
| Serialization | **`serde`** + `serde_json` / `toml` / `serde_yaml` (when YAML is unavoidable) | `#[derive(Serialize, Deserialize)]` is the canonical I/O boundary |
| DB | **`sqlx`** | Compile-time-checked SQL, async, multiple backends; alternatives are `sea-orm` (ORM) and `diesel` (sync, mature) |
| Config | **`figment`** or **`config`** + `serde` | Layer env + files; never hard-code |
| Time | **`jiff`** (new code) or **`chrono`** (existing) | `jiff` is the 2026 default (BurntSushi's crate — typed time zones, DST-aware durations, no `unwrap` traps); `chrono` is still the workhorse in existing code; `time` for embedded/no-std |
| Random | **`rand` 0.9+** | `rand::rng()` for thread-local (NOT `thread_rng()` — renamed because `gen` is reserved in edition 2024). Methods renamed: `.gen()` → `.random()`. `rand::distr` (was `rand::distributions`) |

## Preamble / file header

A library or binary entry point:

```rust
//! Brief one-line description of this crate or module.
//!
//! Longer notes here if useful. Doc comments (`//!` for the module, `///` for items)
//! become rustdoc and ship to docs.rs for libraries.

use std::path::Path;

use anyhow::{Context, Result};
use tracing::info;

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    let cfg = load_config(Path::new("config.toml"))
        .context("loading config")?;
    info!(?cfg, "started");
    Ok(())
}
```

A one-off self-contained script — **prefer this over an ad-hoc crate** for anything throwaway. The cargo team's native `cargo -Zscript` is approaching stabilization in 2026 but is **still nightly-only** as of May 2026. On stable, use `rust-script`:

```bash
cargo install rust-script --locked
```

```rust
#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! reqwest = { version = "0.12", features = ["blocking"] }
//! ```
use anyhow::Result;

fn main() -> Result<()> {
    let body = reqwest::blocking::get("https://example.com")?.text()?;
    println!("{}", body.len());
    Ok(())
}
```

`chmod +x script.rs && ./script.rs`. When `cargo -Zscript` stabilizes (watch [cargo#16569](https://github.com/rust-lang/cargo/pull/16569)), the same shape moves to `cargo` with frontmatter `---cargo` blocks. Until then, `rust-script` is the bridge. See [packaging.md](packaging.md) for the scripts-vs-app spectrum.

## Modern syntax cheat sheet (edition 2024)

| Use | Don't use |
|---|---|
| `let-else` — `let Some(x) = opt else { return; };` (stable 1.65) | nested `match` / `if let` just to extract one value |
| `if let` chains — `if let Some(a) = x && let Some(b) = y && a == b { ... }` (stable 1.88, **edition-2024-gated**) | nested `if let` ladders |
| `if let` guards in match arms — `Some(n) if let Ok(v) = n.parse() => …` (stable 1.95) | hoisting a nested `match` |
| `cfg_select! { unix => fn here() {}, _ => fn here() {} }` (stable 1.95) | the `cfg-if` external crate |
| `?` for fallible propagation | `match` + `return Err(...)` boilerplate |
| `.context("loading config")?` (anyhow) or `.map_err(MyErr::Config)?` (thiserror) | bare `?` with no context on app code |
| `String::new()` / `Vec::new()` then push | `format!()` / `vec!` when you mean a single value |
| `&str` parameter, return `String` | accepting `String` when you only read |
| `impl Into<String>` (or `impl AsRef<Path>`) parameters when you need to be flexible | requiring a specific concrete type |
| `for x in &v` (borrow) / `for x in v` (consume) — pick deliberately | iter().for_each() when a for-loop is clearer |
| `iter().map(...).collect::<Vec<_>>()` with turbofish | bare `.collect()` when the target type is ambiguous |
| `match` on an exhaustive enum, no `_` arm | `_ =>` catch-all that swallows future variants |
| `#[derive(Debug, Clone)]` (and `Copy` only when cheap) | hand-written impls when derive works |
| `#[non_exhaustive]` on public enums/structs you'll extend | breaking changes when adding a variant |
| `Box::new(...)` for trait objects, `Arc::new(...)` for shared ownership | `Box` when sharing across threads, `Rc` in async code |
| `tokio::sync::Mutex` if a guard crosses `.await`; `std::sync::Mutex` otherwise (it's fine *between* awaits) | mixing them — a sync `Mutex` *held across* `.await` can deadlock the runtime |
| `thread::scope(|s| { s.spawn(...) })` for borrowed thread data | `Arc` + `clone` just to satisfy `'static` |
| `OnceLock<T>` / `LazyLock<T>` for lazy statics | `lazy_static!` macro |
| `std::sync::Arc<str>` / `Arc<[u8]>` for shared immutable strings/buffers | `Arc<String>` / `Arc<Vec<u8>>` (double indirection) |
| `let _ = result;` to deliberately ignore a `#[must_use]` | omitting it (clippy warns) |
| `dbg!(value)` while debugging | `println!("{:?}", value)` (then leaving it behind) |

## Ownership reflexes

The borrow checker has a short, learnable rulebook. Most "fights" come from applying the wrong tool, not the wrong code:

| Situation | Tool |
|---|---|
| Function reads a value, doesn't store it | `&T` parameter (shared borrow) |
| Function mutates a value in place | `&mut T` parameter (unique borrow) |
| Function needs to own / store the value | `T` by value (caller decides whether to `clone` or move) |
| Multiple owners, single-threaded | `Rc<T>` |
| Multiple owners, multi-threaded / async | `Arc<T>` |
| Interior mutability, single-threaded | `RefCell<T>` (runtime borrow check) or `Cell<T>` (Copy values) |
| Interior mutability, multi-threaded | `Mutex<T>` / `RwLock<T>` (std for sync code, tokio for async) |
| Atomic counter / flag | `AtomicUsize` / `AtomicBool` (no lock needed) |
| Lazy global | `LazyLock<T>` (no init args) or `OnceLock<T>` (init args via `.get_or_init`) |
| Borrow with explicit lifetime tied to input | name the lifetime: `fn longest<'a>(a: &'a str, b: &'a str) -> &'a str` |
| Trait object | `Box<dyn Trait>` (owned), `&dyn Trait` (borrowed), `Arc<dyn Trait + Send + Sync>` (shared async) |

If you're reaching for `Arc<Mutex<T>>` early, pause. Usually the right shape is **one owner with channels** (`tokio::sync::mpsc`) or **scoped threads** that share a borrow.

See [types.md](types.md) for the deep dive on lifetimes, traits, and smart pointers.

## Error handling at a glance

```rust
// LIBRARY — typed errors via thiserror
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("config not found at {path}")]
    NotFound { path: std::path::PathBuf },
    #[error("invalid TOML: {0}")]
    Invalid(#[from] toml::de::Error),
    #[error("io error")]
    Io(#[from] std::io::Error),
}

pub fn load_config(path: &std::path::Path) -> Result<Config, ConfigError> {
    let text = std::fs::read_to_string(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => ConfigError::NotFound { path: path.into() },
        _ => ConfigError::Io(e),
    })?;
    Ok(toml::from_str(&text)?)
}
```

```rust
// APPLICATION — opaque errors via anyhow
use anyhow::{Context, Result};

fn run() -> Result<()> {
    let cfg = load_config("config.toml".as_ref())
        .context("loading config")?;
    do_thing(&cfg).context("running main thing")?;
    Ok(())
}
```

Rules of thumb:

- **Libraries return typed errors.** Callers need to match on variants. Use `thiserror`.
- **Applications return opaque errors with context.** No one matches on them; they get logged. Use `anyhow`.
- **`?` propagates** — combine with `.context(...)` (anyhow) or `From` impls (thiserror) so the type at every `?` is sound.
- **`panic!`/`unwrap`/`expect` only for programmer bugs**, never for expected failure modes. `expect("invariant: foo always positive")` documents intent.

See [errors.md](errors.md) for the full pattern catalog.

## Universal rules

These apply across binaries, libraries, and one-off scripts:

1. **Treat clippy warnings as errors in CI.** `cargo clippy --workspace --all-targets --all-features -- -D warnings`. The clippy-clean codebase is the readable one.
2. **`cargo fmt` is non-negotiable.** Pre-commit hook, CI check, or both. Style debates are over.
3. **Public APIs get dense rustdoc (`///`).** Every public item: purpose, invariants, non-obvious edge cases — not a restatement of the signature or a walkthrough of the body. Examples in doc tests when they teach usage. Private helpers: usually no doc comment unless the invariant is subtle. Inline comments explain *why*, never *what* the next lines already say; delete process/migration/restatement slop on sight (see the `no-comment-slop` rule). `cargo doc --no-deps --open` to preview.
4. **Errors are typed at module boundaries.** Within a function: `?` and let the type system flow. Across modules: a real error type.
5. **`unwrap`/`expect` are rare and intentional.** When you use one, write `expect("…explanation of why this can't fail…")` — clippy has a lint that prefers `expect` over `unwrap` for exactly this reason.
6. **Newtype before bare primitives** for IDs, currencies, units. `UserId(u64)`, `Cents(i64)`. Free type safety, zero runtime cost.
7. **`#[must_use]` on functions whose result you really want callers to use.** Builder methods, validators, anything where ignoring the return is almost certainly a bug.
8. **`#[non_exhaustive]` on public enums/structs you'll evolve.** Lets you add variants without a breaking change.
9. **Don't `clone()` to dodge the borrow checker.** Reach for `&T`, `Cow<T>`, `Arc<T>`, or restructure the call graph first. A `clone` should be a deliberate choice.
10. **Don't hold a `std::sync::Mutex` across `.await`.** It can deadlock the runtime. Use `tokio::sync::Mutex`, or drop the guard before the await.
11. **Use `tracing`, not `println!`, in anything that isn't a one-off script.** Spans give you structured context for free.
12. **Pin your toolchain per project** via `rust-toolchain.toml`. Builds become reproducible and CI matches local.

## Stdlib reflexes worth knowing

| Use | Instead of |
|---|---|
| `Path::new(...)`, `PathBuf::from(...)`, `path.join(...)` | string concatenation for paths |
| `std::fs::read_to_string(path)?` | open + read loop |
| `Vec::with_capacity(n)` when `n` is known | starting empty + push'ing into many reallocs |
| `String::with_capacity(n)` likewise | same |
| `iter.collect::<Result<Vec<_>, _>>()` to short-circuit on first error | manual loop |
| `iter.try_fold(init, ...)` for fold-with-errors | match-in-loop |
| `Option::as_deref()` / `Result::as_deref()` to go `&Option<String> → Option<&str>` | manual `as_ref().map(|s| s.as_str())` |
| `Option::ok_or(...)` / `Option::ok_or_else(...)` to convert to Result | `match opt { Some(v) => Ok(v), None => Err(...) }` |
| `.copied()` / `.cloned()` deliberately on iterators of references | accidental `.collect::<Vec<&T>>()` |
| `mem::take(&mut field)` to move out of `&mut self` | `clone` + reassign |
| `mem::replace(&mut field, new)` to swap | same |
| `std::sync::OnceLock<T>` / `LazyLock<T>` | `lazy_static!` macro |
| `std::thread::scope(|s| ...)` for borrowed thread data (1.63+) | `Arc::clone` + spawn just to satisfy `'static` |
| `dbg!(expr)` (prints file:line + expr, returns the value) | `println!("{:?}", expr)` |

## When Rust isn't the right tool

Switch languages when you hit any of:

- **A throwaway shell glue script.** Bash, Python, or `uv run script.py` are faster to write, and the compile-time safety isn't paying for itself.
- **Heavy data-frame / numerical exploration.** Polars in Rust is excellent for libraries, but for interactive analysis Python + Polars/Pandas is the better dev loop.
- **A simple Slack bot or one-page web tool with a 1-hour deadline.** TypeScript or Python will ship faster.
- **Plugin host for untyped scripting users.** Lua, Python, or JS embed better than asking your users to write Rust.

Rust is great at: long-running services, CLIs you want to ship as a single binary, embedded/firmware, performance-critical libraries called from other languages, anywhere correctness > iteration speed.

## Don't / Do

| Don't | Do |
|---|---|
| `.unwrap()` in library code | typed error + `?` |
| `Box<dyn std::error::Error>` as a public error type | `thiserror` enum (library) or `anyhow::Error` (application) |
| Catch-all `_ =>` on exhaustive enums | enumerate every variant; let the compiler flag new ones |
| `String` everywhere | `&str` for parameters you only read; `String` only when you own |
| `clone()` to silence the borrow checker | borrow correctly, or restructure ownership |
| `Arc<Mutex<T>>` reflex | one owner + channels, scoped threads, or `RwLock` if reads dominate |
| `std::sync::Mutex` across `.await` | `tokio::sync::Mutex`, or drop guard before await |
| `println!` for logging | `tracing::info!`/`debug!`/`error!` with structured fields |
| `format!("{}", x).parse::<i32>().unwrap()` round-trip | use the value's existing type or `TryFrom` |
| `Vec<&T>` returned from function with local lifetime | return `Vec<T>` or borrow with explicit lifetime tied to input |
| `for i in 0..v.len() { v[i] }` | `for x in &v` |
| `let x = if cond { 1 } else { 0 }; …` then `if x == 1 { … }` | branch directly in the original `if` |
| `Result<T, Box<dyn Error>>` in your own code | a real error type |
| `match opt { Some(x) => f(x), None => panic!() }` | `opt.expect("invariant: …")` or proper error |
| `cargo test` | `cargo nextest run` (faster, better output, real isolation) |
| `lazy_static! { static ref X: T = ... }` | `static X: LazyLock<T> = LazyLock::new(\|\| ...);` |
| Re-implementing `From`/`TryFrom` manually | `#[from]` on a `thiserror` variant |
| Trait objects everywhere | generics + `impl Trait` first; `dyn` only when you need heterogeneous storage or dynamic dispatch |
| `if let Some(x) = opt { x } else { return; }` | `let Some(x) = opt else { return; };` |
| Nested `if let` chains | `if let Some(a) = x && let Some(b) = y { ... }` (edition 2024) |
| `.iter().map(...).collect::<Vec<_>>()` for a one-shot in-place transform | `Vec::extend` / `for` loop / in-place mutation |
| Forgetting `#[derive(Debug)]` on public types | derive `Debug` (and `Clone`/`PartialEq`/`Eq`/`Hash` as warranted) for any type a caller might log |
| Hand-rolled `Display` to `format!` then `parse` round-trip | dedicated `From`/`Into` or `serde` impls |
