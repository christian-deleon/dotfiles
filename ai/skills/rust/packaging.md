# Packaging

Rust's packaging is one of the strongest in any language ecosystem — one tool (`cargo`), one manifest (`Cargo.toml`), one lockfile (`Cargo.lock`), and a single registry (`crates.io`). There are no alternatives to learn. The interesting decisions are about *shape*: binaries vs libraries, single crate vs workspace, feature flags, and what to ship.

## The crate shapes

Pick by what you're building:

| Shape | Layout | When |
|---|---|---|
| **Binary crate** | `src/main.rs` (+ optional `src/bin/*.rs`) | A CLI, daemon, or service — anything that produces an executable |
| **Library crate** | `src/lib.rs` | Code you'll consume from another crate (your own or someone else's) |
| **Library + binary** | both `src/lib.rs` and `src/main.rs` | Common pattern: put the logic in `lib.rs`, keep `main.rs` thin (arg parsing + call into lib). Lets you write integration tests against the library |
| **Workspace** | top-level `Cargo.toml` with `[workspace]`, members in subdirs | Multiple crates that depend on each other and share `Cargo.lock`/`target/` |
| **Single-file script** | one `.rs` file with inline `Cargo.toml` | Throwaway tooling; see "Scripts" below |

The lib+bin pattern is the right default for any non-trivial CLI:

```
my-cli/
├── Cargo.toml
└── src/
    ├── lib.rs           # all the logic, public API, doc tests
    ├── main.rs          # arg parsing, calls into lib.rs
    └── bin/
        └── another.rs   # second binary (optional)
```

`main.rs` stays under ~50 lines. Everything testable lives in `lib.rs`. Integration tests in `tests/` can `use my_cli::*`.

## `Cargo.toml` — the manifest

Set `rust-version` honestly — under the edition-2024 / resolver-3 era, it's load-bearing for dependency resolution. The MSRV-aware resolver (default in resolver 3) prefers older-but-compatible dep versions when a newer one would require a Rust newer than your declared `rust-version`. Declaring it accurately keeps `cargo add` and `cargo update` from silently bumping your MSRV.

A canonical binary crate `Cargo.toml`:

```toml
[package]
name = "my-app"
version = "0.1.0"
edition = "2024"
rust-version = "1.85"
authors = ["Christian De Leon <christian.deleon12@proton.me>"]
license = "MIT OR Apache-2.0"
description = "One-sentence description that shows up on crates.io"
repository = "https://github.com/USER/my-app"
homepage = "https://github.com/USER/my-app"
documentation = "https://docs.rs/my-app"
readme = "README.md"
keywords = ["cli", "thing"]                  # max 5, alphanumeric
categories = ["command-line-utilities"]      # see https://crates.io/category_slugs
include = ["src/**/*", "Cargo.toml", "README.md", "LICENSE-*"]

[dependencies]
anyhow = "1"
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

[dev-dependencies]
pretty_assertions = "1"
insta = { version = "1", features = ["yaml"] }

[build-dependencies]
# (rare — only if you have a build.rs that needs deps)

[lints.rust]
unsafe_code = "forbid"

[lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
```

### Required fields for publishing

For a crate you'll push to crates.io: `name`, `version`, `edition`, `description`, `license` (or `license-file`), and `repository`/`homepage`. `cargo publish` will error without them.

### `edition` and `rust-version`

| Field | What |
|---|---|
| `edition = "2024"` | Language edition. New crates: always 2024. Old crates: bump with `cargo fix --edition` |
| `rust-version = "1.85"` | MSRV — minimum supported Rust. `cargo` will refuse to compile on older toolchains and print a clear error. Bump consciously |

### Version constraints

Cargo uses SemVer with Caret (`^`) as the default operator:

| Spec | Means |
|---|---|
| `"1.2.3"` (or `"^1.2.3"`) | `>= 1.2.3, < 2.0.0` (default; "compatible with 1.2.3") |
| `"~1.2.3"` | `>= 1.2.3, < 1.3.0` (tilde — patch updates only) |
| `"=1.2.3"` | exactly `1.2.3` (don't use this unless you have a *reason*) |
| `">= 1.2, < 1.5"` | manual range |
| `"*"` | any version (forbidden on crates.io) |

The default caret behavior is what you want. Pin exact versions only when you've found a bug in a specific dep version.

### Dependency-table forms

```toml
[dependencies]
# short form — just the version
anyhow = "1"

# table form — version, features, default-features
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls", "json"] }

# git dependency
my-private-crate = { git = "https://github.com/me/crate", tag = "v0.3.0" }

# path dependency (within a workspace, or local develop)
my-shared = { path = "../my-shared" }

# optional dependency — only included when a feature turns it on
postgres = { version = "0.19", optional = true }

# rename a crate (rare but handy when two registries collide)
url2 = { package = "url", version = "2" }
```

### Choosing features carefully

Many large crates compile huge amounts of code by default. Disable defaults and opt in to what you need:

```toml
reqwest = { version = "0.13", features = ["json"] }                                     # rustls is default since 0.13
tokio = { version = "1", features = ["macros", "rt-multi-thread", "net", "io-util"] }   # libraries
tokio = { version = "1", features = ["full"] }                                          # apps
serde = { version = "1", features = ["derive"] }
sqlx = { version = "0.8", default-features = false, features = ["runtime-tokio", "postgres", "tls-rustls", "uuid", "chrono"] }
```

Libraries should be **narrow** with features; applications can use the kitchen-sink `"full"` if compile time isn't critical. The cost is real:

- `tokio` with `"full"` adds ~2× compile time vs. minimal features.
- `reqwest` 0.13+ defaults to `rustls` (pure Rust, no OpenSSL/C toolchain). Only opt back into native-tls (`default-features = false, features = ["native-tls", ...]`) if you specifically need the OS trust store (corporate certs on Windows/macOS).

### `[features]` — your own feature flags

```toml
[features]
default = ["json"]                          # what gets enabled if user opts in by name only
json = ["dep:serde", "dep:serde_json"]      # gated on optional deps
postgres = ["dep:sqlx", "sqlx/postgres"]
unstable = []                                # for opt-in unstable APIs in libs
```

Rules:

- Features are **additive**. Turning a feature on in one consumer must not change behavior for another. Never use features to mean "build differently."
- **No mutually-exclusive features.** If A and B can't both be on, your crate will eventually find itself in a dep graph where both get enabled and you'll have a compile error. Pick a runtime flag instead.
- Optional deps go in `[dependencies]` with `optional = true`, then a feature with `dep:that_crate` activates it.
- `default = [...]` is the feature set used when consumers add your crate without specifying features. Be conservative — pulling in big optional features by default is a footgun.

Activating features in dependent code:

```rust
#[cfg(feature = "json")]
pub fn to_json(&self) -> String { serde_json::to_string(self).unwrap() }
```

## Workspaces

Workspaces let multiple crates share one `Cargo.lock`, one `target/`, and one set of dependency versions:

```
my-project/
├── Cargo.toml          # workspace root
├── Cargo.lock          # single shared lockfile
├── crates/
│   ├── core/
│   │   ├── Cargo.toml
│   │   └── src/lib.rs
│   ├── cli/
│   │   ├── Cargo.toml
│   │   └── src/main.rs
│   └── api/
│       ├── Cargo.toml
│       └── src/lib.rs
└── target/             # shared build artifacts
```

```toml
# my-project/Cargo.toml
[workspace]
resolver = "3"
members = ["crates/*"]

[workspace.package]
edition = "2024"
rust-version = "1.85"
version = "0.1.0"
license = "MIT OR Apache-2.0"
authors = ["Christian De Leon"]
repository = "https://github.com/me/my-project"

[workspace.dependencies]
anyhow = "1"
thiserror = "2"
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"

[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
```

```toml
# crates/cli/Cargo.toml
[package]
name = "my-project-cli"
edition.workspace = true
rust-version.workspace = true
version.workspace = true
license.workspace = true
authors.workspace = true
repository.workspace = true

[dependencies]
my-project-core = { path = "../core" }
anyhow.workspace = true
tokio.workspace = true
tracing.workspace = true

[lints]
workspace = true
```

**Pitfall:** a crate that sets `[lints] workspace = true` **cannot also add its own `[lints.rust]` or `[lints.clippy]` keys** — it's a hard error. Pick one mode per crate: either inherit the workspace policy fully, or define the lints locally. If one crate needs a different policy, declare its `[lints.rust]` / `[lints.clippy]` block locally and don't set `workspace = true`.

### When to introduce a workspace

- **Yes:** Multiple binaries that share library code. A library you want to test against its own binary. CI matrix across "minimal" and "full" features.
- **Yes:** Build-time isolation — proc-macro crates *must* live in their own crate, and big slow deps are easier to cache in a separate crate.
- **No:** A single binary with a few modules. That's just `src/` — modules, not crates.
- **No:** Splitting things just to feel organized. Cross-crate refactors are more friction than cross-module refactors.

### `resolver = "3"`

Edition 2024 → resolver 3 (since Rust 1.84). Two effects:

1. **Per-edition feature unification** — an old crate in your tree won't accidentally get features that require a newer edition.
2. **MSRV-aware resolution by default** — `incompatible-rust-versions = "fallback"` is flipped on. The resolver prefers a dep version compatible with your declared `rust-version` over a newer one that would require a newer toolchain.

**You only have to set `resolver = "3"` explicitly at a *virtual* workspace root** (no `[package]` at the root). Workspaces with a root `[package]` infer the resolver from the package's `edition`. For non-workspace crates, the edition implies the resolver and there's nothing to set.

## `src/bin/` — multiple binaries from one crate

A crate can ship multiple binaries by putting each in `src/bin/<name>.rs`:

```
src/
├── lib.rs              # shared library
├── main.rs             # default binary — `cargo run`
└── bin/
    ├── server.rs       # `cargo run --bin server`
    ├── worker.rs       # `cargo run --bin worker`
    └── migrate.rs      # `cargo run --bin migrate`
```

Each binary's `main` function can `use my_crate::*` to share code. Useful when the binaries are tightly related — one HTTP server, one worker, one migration tool, all sharing the same library.

For unrelated tools, prefer a workspace. The single-crate pattern shines when the binaries truly share most of their dependencies.

## `examples/`

Files in `examples/<name>.rs` compile as small standalone binaries that link against your crate. They are the documentation of your library:

```bash
cargo run --example basic
cargo run --example streaming -- --url https://example.com
```

```rust
// examples/basic.rs
use my_lib::Client;

fn main() {
    let client = Client::new("token");
    println!("{:?}", client.fetch("/users/me"));
}
```

Conventions:

- Examples must compile under `cargo build --examples`. CI runs this — broken examples = broken docs.
- Use `examples/` for showcasing the library, not for ad-hoc tools (those belong in `src/bin/`).
- Subdirectories: `examples/auth/main.rs` works (set `[[example]]` if you want a custom name).

## `tests/` — integration tests

Each file in `tests/` is a separate test binary that depends on your crate's *public* API:

```rust
// tests/api.rs
use my_lib::Client;

#[tokio::test]
async fn end_to_end() {
    let c = Client::new(":memory:");
    assert_eq!(c.ping().await.unwrap(), "pong");
}
```

Differences from unit tests:

- Compile separately — slower than inline `#[cfg(test)] mod tests`.
- Can only use the public API. Forces you to test the contract, not internals.
- Each `tests/*.rs` is its own crate. Shared helpers go in `tests/common/mod.rs` (note: a directory with `mod.rs` — not `tests/common.rs`, which would be run as a test binary).

## `build.rs` — build scripts

A `build.rs` at the crate root runs *before* the crate compiles. Use it for:

- Generating Rust source from external files (Protobuf, schema definitions).
- Compiling and linking C/C++ via the `cc` crate.
- Probing for system libraries via `pkg-config`.
- Emitting `cargo:rerun-if-changed=…` and `cargo:rustc-cfg=…` directives.

```rust
// build.rs
fn main() {
    // Re-run only when this file or schemas change.
    println!("cargo:rerun-if-changed=schemas/");

    // Compile vendored C code.
    cc::Build::new().file("native/wrapper.c").compile("wrapper");

    // Pass a config flag to the crate.
    if std::env::var("CARGO_FEATURE_FOO").is_ok() {
        println!("cargo:rustc-cfg=has_foo");
    }
}
```

```toml
[build-dependencies]
cc = "1"
```

Rules:

- `build.rs` is its own compilation unit. Its dependencies go in `[build-dependencies]`, separate from `[dependencies]`.
- Print `cargo:rerun-if-changed=PATH` for every file the build script reads. Otherwise cargo re-runs it on every build.
- Avoid network access in `build.rs` — it makes builds non-reproducible and breaks offline builds. If you really need it, vendor the artifact at publish time.
- Heavy build scripts (codegen, C compilation) are the most common cause of "Rust is slow to compile" complaints. Treat the time spent here as worth optimizing.

## Scripts — running a single `.rs` file

For throwaways in May 2026, in order of preference:

1. **`rust-script`** — the stable bridge until cargo's native script support lands:

   ```bash
   cargo install rust-script --locked
   ```

   ```rust
   #!/usr/bin/env rust-script
   //! ```cargo
   //! [dependencies]
   //! reqwest = { version = "0.13", features = ["blocking"] }
   //! ```

   fn main() -> Result<(), Box<dyn std::error::Error>> {
       let body = reqwest::blocking::get("https://example.com")?.text()?;
       println!("{}", body.len());
       Ok(())
   }
   ```

   `chmod +x script.rs && ./script.rs`.

2. **`cargo -Zscript`** (nightly only — stabilization in FCP early 2026, [cargo#16569](https://github.com/rust-lang/cargo/pull/16569)). When it lands, the shape becomes `cargo run script.rs` with a `---cargo`-fenced frontmatter block. Until then, don't rely on it for anything you ship.

3. **A real crate.** `cargo new --bin throwaway` is fine. For anything you'll keep, this is the right answer.

For one-shot tools that don't need crates.io deps, `cargo new --bin` and `cargo run` is the boring, reliable path.

## Publishing to crates.io

```bash
cargo login                                   # token from crates.io/me — only once per machine
cargo publish --dry-run                       # validate
cargo publish                                 # ship it (no take-backs except `cargo yank`)
cargo yank --version 0.2.1                    # discourage installs of a bad version
cargo yank --version 0.2.1 --undo             # undo a yank
```

Checks before publishing:

- `cargo doc --no-deps` builds clean.
- `cargo public-api diff` shows no surprise breaking changes (for v1+ crates).
- `cargo semver-checks check-release` passes.
- `cargo audit` is clean.
- `README.md`, `LICENSE-MIT`, `LICENSE-APACHE` exist; `include = [...]` in `Cargo.toml` lists them.
- The `description`, `repository`, and `categories` fields are filled in.
- `rust-version` matches what you actually test against in CI.

### SemVer hygiene for libraries

Cargo follows SemVer with the Rust convention that `0.x.y` treats `x` as the major component. Specifically:

- `0.1.0 → 0.1.1`: bugfix only, no breaking changes.
- `0.1.0 → 0.2.0`: breaking changes allowed.
- `1.0.0 → 1.1.0`: backward-compatible features and additions.
- `1.0.0 → 2.0.0`: breaking changes allowed.

Hidden footguns:

- Adding a required method to a public trait is a breaking change. Use `#[non_exhaustive]` and/or default impls.
- Adding a new variant to a public enum is a breaking change unless the enum is `#[non_exhaustive]`.
- Adding a new field to a public struct is a breaking change unless the struct has private fields or is `#[non_exhaustive]`.
- Changing a function signature (parameters, return type) is always breaking.

`cargo semver-checks check-release` catches most of these mechanically. Run it before tagging.

## `.cargo/config.toml` — registry, build, target config

Per-project `.cargo/config.toml` (committed) for project-wide build settings:

```toml
[build]
target-dir = "target"
rustflags = ["-W", "clippy::pedantic"]

[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]

[registries]
my-private = { index = "sparse+https://my-corp-registry/" }
```

User-level `~/.cargo/config.toml` is the same format. Don't put credentials there — they go in `~/.cargo/credentials.toml` and shouldn't be committed.

## `.gitignore` — what to commit

```gitignore
/target
```

That's it. **Commit `Cargo.lock` for both binaries and libraries.** The Cargo team [reversed the old "don't commit lockfile for libraries" guidance in August 2023](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html) — reproducible CI matters more than the historical concern about consumers picking versions, and Dependabot/Renovate handle the "test against newest deps" case cleanly via a separate CI matrix entry that runs `cargo update` first. The 2026 default is "commit it; deviate only with a reason."

## Crate name conventions

- **Snake case** for crate names that are also Rust idents: `my_crate`, `serde_json`.
- **Kebab case** is acceptable on crates.io and many crates use it: `serde-json` ← `serde_json` (cargo automatically maps `serde-json` package name to `serde_json` Rust ident).
- One name per concept. `my-tool-cli` for the binary if there's also `my-tool` the library.
- Reserved namespaces (`std`, `core`, `alloc`, `proc_macro`, `test`) — don't shadow them.

## Common Cargo.toml mistakes

| Mistake | Fix |
|---|---|
| `tokio = "1"` with default features in a library | Narrow features: `features = ["macros", "rt"]` |
| `reqwest = "0.12"` (uses default OpenSSL) | `default-features = false, features = ["rustls-tls", "json"]` |
| Missing `rust-version` field | Add it; pin to what you test |
| `edition = "2021"` in a new crate | `"2024"` |
| No `resolver = "3"` at workspace root | Add it |
| `[[bin]]` table when `src/main.rs` is the only binary | Cargo infers it; remove the explicit table |
| Path deps without versions in a published crate | Path deps must have a version field if you `cargo publish` (cargo strips the path on publish but the version is what gets resolved) |
| Adding `cargo` (without `--locked`) in CI | Use `cargo install <tool> --locked` always |
| `[features] default = ["all-the-things"]` | Be conservative; users opt in |
