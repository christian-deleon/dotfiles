# Tooling

Rust's tooling story has always been consolidated — `cargo` does almost everything out of the box. The 2026 stack adds three external pieces on top of cargo: `clippy` (the lint), `rustfmt` (the formatter), and `cargo-nextest` (the test runner). Everything else (`cargo-watch`, `cargo-audit`, `cargo-deny`, `cargo-edit`) is opt-in convenience.

The default stack is `rustup` + `cargo` + `clippy` + `rustfmt` + `nextest`. Treat warnings as errors in CI. Pin your toolchain per project so builds are reproducible.

## `rustup` — toolchain management

`rustup` installs and switches Rust toolchains. One per host; the toolchain version is the global default unless overridden per project.

```bash
rustup install stable                 # default everyone should have
rustup install 1.85                   # pin to a specific version
rustup install nightly                # only when a feature requires it

rustup default stable                 # set the global default
rustup show                           # see what's active
rustup update                         # update all installed toolchains

rustup component add clippy rustfmt rust-src   # extras you'll want
rustup component add rust-analyzer             # the LSP (also ships with VS Code's Rust extension)
rustup target add wasm32-unknown-unknown       # cross-compile target
```

### Per-project pinning — `rust-toolchain.toml`

Drop this at the workspace root:

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.85"                  # or "stable", "nightly-2025-02-15"
components = ["clippy", "rustfmt", "rust-src"]
targets = ["wasm32-unknown-unknown"]
profile = "minimal"
```

`cargo` and `rustup` honor this file: anyone who clones the repo gets exactly your toolchain on first `cargo build`. CI sees the same. Pin every published project this way.

### Sharp edges

- `rustup override set <toolchain>` writes a per-directory override that overrides `rust-toolchain.toml`. Avoid — it's machine-local and surprises collaborators. Use the file.
- `rustup self update` updates `rustup` itself; `rustup update` updates toolchains. Different commands.
- A specific stable version (`1.85`) is reproducible; `stable` floats. Pick consciously.

## `cargo` — build, test, run, doc

`cargo` is the build system. You will not need an alternative.

### Essentials

```bash
cargo new my-app                  # binary crate (src/main.rs)
cargo new --lib my-lib            # library crate (src/lib.rs)
cargo init                        # init in an existing directory

cargo build                       # debug build → target/debug/
cargo build --release             # optimized → target/release/
cargo run                         # build + run the (default) binary
cargo run --bin tool -- --flag    # specific bin, args after `--`
cargo run --example demo          # run examples/demo.rs

cargo check                       # type-check without codegen (much faster than build)
cargo doc --no-deps --open        # render rustdoc and open in browser

cargo test                        # run tests (prefer `cargo nextest run` — see below)
cargo bench                       # run benches (stable supports criterion; built-in benches need nightly)

cargo clean                       # delete target/ — only when something is wrong
```

### Dependency management

```bash
cargo add serde --features derive       # add dep with features
cargo add tokio --features full          # full = sane default for apps; libs should be narrow
cargo add --dev pretty_assertions        # dev-only
cargo add --build cc                     # build-script-only
cargo remove serde

cargo update                              # update deps within version constraints
cargo update --precise 1.0.5 anyhow      # pin one dep to an exact version
cargo tree                                # render the dep graph (use `--duplicates` for dupes)
cargo tree -i some_crate                  # who depends on `some_crate`
```

`cargo add` and `cargo remove` are built-in since 1.62 — you don't need `cargo-edit` anymore.

### Workspaces

A multi-crate workspace shares one `Cargo.lock` and one `target/`:

```toml
# Cargo.toml (workspace root)
[workspace]
resolver = "3"   # edition 2024 → resolver 3
members = ["crates/*"]

[workspace.package]
edition = "2024"
rust-version = "1.85"
license = "MIT OR Apache-2.0"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
anyhow = "1"
thiserror = "2"
tracing = "0.1"
```

Members inherit:

```toml
# crates/myapp/Cargo.toml
[package]
name = "myapp"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
license.workspace = true

[dependencies]
serde.workspace = true
tokio.workspace = true
anyhow.workspace = true
tracing.workspace = true
```

See [packaging.md](packaging.md) for the deep dive on `Cargo.toml`, features, and publishing.

### Build profiles

```toml
# Cargo.toml
[profile.dev]
opt-level = 1                # default 0 is unbearably slow for any nontrivial work
debug = true

[profile.release]
opt-level = 3
lto = "thin"                 # link-time optimization
codegen-units = 1            # smaller binary, slower compile
strip = "symbols"

[profile.dev.package."*"]
opt-level = 3                # optimize dependencies even in dev — huge win
```

`opt-level = 1` for your own code in dev gives 90% of release-mode speed for ~10% of release-mode compile cost. The `[profile.dev.package."*"]` trick optimizes *deps* at -O3 while keeping your code at -O1 — the dev loop stays fast but `tokio`, `serde`, and friends are no longer molasses.

## `clippy` — the lint

`clippy` is the lint, not optional. It catches bugs the type checker can't and modernizes idioms across editions.

```bash
cargo clippy                              # run on the current crate
cargo clippy --workspace --all-targets --all-features
cargo clippy --fix                        # auto-apply safe fixes
cargo clippy -- -D warnings               # promote warnings to errors (use in CI)
```

### Lint groups

| Group | Default | Use it? |
|---|---|---|
| `clippy::correctness` | error | always |
| `clippy::suspicious` | warn | always |
| `clippy::style` | warn | always |
| `clippy::complexity` | warn | usually |
| `clippy::perf` | warn | always |
| `clippy::pedantic` | allow | opt-in per crate; many are noisy |
| `clippy::nursery` | allow | unstable; opt-in for early feedback |
| `clippy::cargo` | allow | useful in CI for `Cargo.toml` hygiene |

### Recommended `Cargo.toml` `[lints]` table

```toml
# Cargo.toml (workspace root or per crate)
[lints.rust]
unsafe_code = "forbid"          # opt back in per file with `#![allow(unsafe_code)]`
missing_docs = "warn"           # libraries; tighten to "deny" for published crates
unreachable_pub = "warn"

[lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
nursery = { level = "warn", priority = -1 }
cargo = { level = "warn", priority = -1 }

# Pedantic noise you can live without
module_name_repetitions = "allow"
must_use_candidate = "allow"
missing_errors_doc = "allow"
missing_panics_doc = "allow"
```

The `[lints]` table (stable since 1.74) is the modern way to configure lints — no more `#![warn(clippy::pedantic)]` scattered in `lib.rs`. Workspace-level `[workspace.lints]` + per-crate `[lints] workspace = true` keeps the policy in one place.

### `clippy.toml`

For lints that take parameters:

```toml
# clippy.toml at workspace root
msrv = "1.85"                            # minimum supported rust version
type-complexity-threshold = 750
too-many-arguments-threshold = 8
disallowed-methods = [
    { path = "std::env::var", reason = "use the config crate instead" },
]
```

## `rustfmt` — the formatter

No bikeshed. One style for the whole ecosystem.

```bash
cargo fmt                                 # format the whole crate
cargo fmt --check                         # CI mode; exits non-zero on diffs
cargo fmt -- --emit=files src/main.rs     # format one file
```

### `rustfmt.toml`

Keep it minimal:

```toml
edition = "2024"
max_width = 100
imports_granularity = "Module"          # nightly-only options noted below
group_imports = "StdExternalCrate"       # nightly-only
```

The unstable options above (`imports_granularity`, `group_imports`) require `cargo +nightly fmt`. Either accept the trade or omit them — most teams run rustfmt with `edition` as the only knob.

## `cargo-nextest` — test runner

`cargo nextest` is the test runner you actually want. It:

- Runs each test in its own process (real isolation; one panic doesn't poison the rest).
- Parallelizes more aggressively than `cargo test`.
- Has a much better failure summary.
- Supports per-test timeouts, retries, and flaky-test detection.

```bash
cargo install cargo-nextest --locked
cargo nextest run                                      # all tests
cargo nextest run -E 'test(=specific_test)'            # filter
cargo nextest run --workspace --all-features
cargo nextest run --retries 2                          # retry flaky tests
cargo nextest list                                     # see what would run
```

`cargo nextest` does not run doc tests (those use `rustdoc`'s test harness). Run both in CI:

```bash
cargo nextest run --workspace --all-features
cargo test --doc --workspace --all-features
```

### Test layout

```
src/
  lib.rs            # unit tests in `#[cfg(test)] mod tests { ... }` at the bottom of each module
tests/              # integration tests (each file = its own crate)
  api.rs
  cli.rs
benches/            # criterion benchmarks
examples/           # `cargo run --example name`
```

Inline unit test pattern:

```rust
pub fn add(a: i32, b: i32) -> i32 { a + b }

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn add_works() {
        assert_eq!(add(2, 3), 5);
    }

    #[test]
    #[should_panic(expected = "divide by zero")]
    fn divide_panics() {
        let _ = 1 / 0;
    }
}
```

Async test:

```rust
#[tokio::test]
async fn fetch_works() {
    let body = reqwest::get("https://example.com").await.unwrap().text().await.unwrap();
    assert!(body.contains("Example"));
}
```

`tokio::test` spins up a single-threaded runtime per test (use `#[tokio::test(flavor = "multi_thread")]` for the multi-threaded one).

### Useful test crates

| Crate | Use for |
|---|---|
| `pretty_assertions` | colorized diff on `assert_eq!` failure — install for every project |
| `insta` | snapshot testing; reviewed in-place with `cargo insta review` |
| `proptest` / `quickcheck` | property-based testing |
| `rstest` | parameterized tests with fixtures |
| `criterion` | benchmarks on stable |
| `mockall` / `mockito` | mocks (mockall for trait mocks, mockito for HTTP servers) |
| `wiremock` | async HTTP mocks for reqwest/tokio tests |
| `testcontainers` | spin up real Docker dependencies (Postgres, Redis) for integration tests |

## `cargo-watch` — file-watcher loop

Re-run a command on every save. Removes the cycle of "save, alt-tab, hit up, hit enter":

```bash
cargo install cargo-watch
cargo watch -x check                       # re-run `cargo check` on save
cargo watch -x 'nextest run'               # re-run tests
cargo watch -x clippy -x 'nextest run'     # chain commands
cargo watch -i target -x check             # ignore target/ (it already does by default)
```

A modern alternative is `bacon` — a TUI-driven watcher that's a bit nicer to live with than `cargo-watch`. Either is fine.

## `cargo-audit` / `cargo-deny` — supply chain

`cargo-audit` checks `Cargo.lock` against the [RustSec advisory database](https://rustsec.org/):

```bash
cargo install cargo-audit --locked
cargo audit                                # scan for known CVEs
cargo audit --deny warnings                # CI mode
```

`cargo-deny` is the broader policy tool — bans/allows specific crates, licenses, advisories, and detects duplicate dep versions:

```bash
cargo install cargo-deny --locked
cargo deny check                           # run all configured checks
cargo deny check advisories
cargo deny check licenses
cargo deny check bans                      # ban specific crates / dupes
cargo deny check sources                   # registry/git source allowlist
```

Pair it with `deny.toml`:

```toml
[graph]
all-features = true

[advisories]
db-path = "~/.cargo/advisory-db"
db-urls = ["https://github.com/rustsec/advisory-db"]
yanked = "warn"

[licenses]
allow = ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC", "Unicode-3.0"]
confidence-threshold = 0.93

[bans]
multiple-versions = "warn"
wildcards = "deny"
deny = [
    { name = "openssl-sys", reason = "use rustls" },
]
```

Run both in CI. `cargo-audit` is the fast first-line check; `cargo-deny` is the comprehensive gate.

### Recent supply-chain context (2025–2026)

A run of malicious typosquat crates was removed from crates.io in late 2025 / early 2026 (e.g. `finch-rust`, `polymarket-clients-sdk`). crates.io updated its malicious-crate notification policy in Feb 2026 — RustSec advisories are now always issued for removals. CVE-2026-33056 in Cargo's `tar` handling (patched in Cargo 1.94.1 / 1.93.2 / 1.92.1) is a reminder that keeping `rustc` current isn't enough — Cargo itself ships fixes that you need.

Practical hygiene:

- **Subscribe to the RustSec RSS feed** (`https://rustsec.org/advisories/`).
- **Pin toolchains** (`rust-toolchain.toml`) so a fresh `cargo install` doesn't silently pick up a vulnerable Cargo.
- **`cargo install <tool> --locked`** always — uses the published `Cargo.lock` rather than re-resolving, dodging typosquat windows.
- **Keep `Cargo.lock` committed** (see [packaging.md](packaging.md)).

## Compile speed — when it matters

Compile times are the most common Rust complaint. Don't optimize this until it actually hurts; when it does, in order of payoff:

1. **`opt-level = 1` for dev profile** (shown above). Free; cuts runtime-of-dev-builds by ~10×.
2. **`sccache`** — caches `rustc` output across projects. `cargo install sccache --locked && export RUSTC_WRAPPER=sccache`. Huge for CI; modest for solo dev.
3. **The `cranelift` codegen backend** — faster debug builds (no `--release` payoff). Still **nightly-only** as of May 2026 (stabilization is an active project goal, but not landed). To try it:

   ```bash
   rustup component add rustc-codegen-cranelift-preview --toolchain nightly
   ```

   ```toml
   # ~/.cargo/config.toml
   [unstable]
   codegen-backend = true

   [profile.dev]
   codegen-backend = "cranelift"
   ```

4. **Linker.** On Linux x86_64, **`rust-lld` is already the default since Rust 1.90** — you no longer need to configure anything to get the LLD speedup. `mold` (~3–5× faster than LLD) is the next step up; configure only if you've measured benefit:

   ```toml
   # ~/.cargo/config.toml
   [target.x86_64-unknown-linux-gnu]
   linker = "clang"
   rustflags = ["-C", "link-arg=-fuse-ld=mold"]
   ```

   macOS uses Apple's `ld` (already fast); Windows uses LLD. Linux is the only platform where the linker choice was historically painful — and the 1.90 default fixed the default case.

5. **Workspace splitting.** Move slow-to-compile code (proc macros, big deps) into separate crates so most rebuilds skip them.
6. **Feature gates on deps.** `tokio = { version = "1", features = ["macros", "rt"] }` instead of `features = ["full"]` cuts compile time in libraries where you don't need everything.

## Pre-commit / CI

A minimal CI matrix:

```yaml
# .github/workflows/ci.yml
name: ci
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt
      - uses: Swatinem/rust-cache@v2
      - run: cargo fmt --check
      - run: cargo clippy --workspace --all-targets --all-features -- -D warnings
      - uses: taiki-e/install-action@nextest
      - run: cargo nextest run --workspace --all-features
      - run: cargo test --doc --workspace --all-features
      - uses: taiki-e/install-action@cargo-audit
      - run: cargo audit
```

Pre-commit (optional but common):

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/doublify/pre-commit-rust
    rev: v1.0
    hooks:
      - id: fmt
      - id: clippy
        args: ["--", "-D", "warnings"]
```

If you want one-tool-runs-everything: `cargo install just` and put the recipes in a justfile (see the `just` skill).

## Other cargo subcommands worth knowing

| Subcommand | What it does |
|---|---|
| `cargo expand` | Show macro-expanded output. Indispensable when debugging `#[derive(...)]` issues |
| `cargo machete` | Find unused dependencies |
| `cargo udeps` | Same idea, requires nightly; broader detection |
| `cargo outdated` | Show deps with newer major/minor/patch available |
| `cargo bloat` | What's making the binary big |
| `cargo flamegraph` | Profile and produce a flamegraph (Linux/Mac) |
| `cargo llvm-cov` | Code coverage via LLVM source-based coverage |
| `cargo public-api` | Diff a crate's public API against the previous version — required for SemVer hygiene on libraries |
| `cargo semver-checks` | Check whether the next version respects SemVer; integrate in CI for libraries |
| `cargo-mutants` | Mutation testing — generate code mutations and see which tests catch them |

Install all of them as cargo subcommands:

```bash
cargo install cargo-expand cargo-machete cargo-outdated cargo-bloat cargo-llvm-cov \
              cargo-public-api cargo-semver-checks cargo-mutants --locked
```

`--locked` everywhere — it uses the published `Cargo.lock` for reproducible installs, which dodges malware-typosquat windows on the registry.
