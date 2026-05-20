# Async and Concurrency

Rust has three concurrency tools and they are not interchangeable. Pick by what's blocking:

| Bottleneck | Pick | Why |
|---|---|---|
| I/O-bound, many connections (HTTP, DB, sockets) | **`async` / `tokio`** | One thread (or a small pool) multiplexes thousands of `.await` points cheaply |
| I/O-bound, blocking-only libraries | **threads** (`std::thread`, `tokio::task::spawn_blocking`) | OS threads, no event loop; works with any blocking API |
| CPU-bound, data-parallel work | **`rayon`** | Drop-in parallel iterators, work-stealing pool |
| CPU-bound, irregular fan-out | **`std::thread::scope`** or threads + channels | One thread per chunk of computation |

The most common AI failure mode here is doing blocking work inside an `async fn` (freezes the runtime), holding a `std::sync::Mutex` guard across `.await` (can deadlock), using `tokio::join!`/`tokio::try_join!` instead of `JoinSet` for dynamic fan-out, and reaching for `Arc<Mutex<T>>` for inter-task communication when a channel would be clearer and faster.

## The async mental model

An `async fn` doesn't run — it returns a `Future`, a state machine that the runtime polls:

```rust
async fn fetch(url: &str) -> Result<String> {
    // doesn't execute when the fn is called — only when polled
    let response = reqwest::get(url).await?;
    response.text().await.map_err(Into::into)
}

// Calling it produces a Future but doesn't poll it:
let fut = fetch("https://example.com");        // does nothing yet
let body = fut.await?;                          // runs to completion (or yields)
```

`.await` is a yield point — the current task gives the runtime control until the awaited future is ready. Between awaits, the task runs synchronously on whatever thread the runtime picked.

### What "the runtime" means

A runtime (tokio, async-std (discontinued in 2025 — don't use), smol, glommio) provides:

- An **executor** — schedules futures across one or more OS threads.
- A **reactor** — wraps OS I/O syscalls (epoll/kqueue/io_uring) so a parked task wakes up when its file descriptor is ready.
- **Timers, channels, sync primitives** designed to interact with the executor.

In 2026, **`tokio` is the default**. The ecosystem (`axum`, `reqwest`, `sqlx`, `tonic`, `hyper`) all target it. Pick a different runtime only with a specific reason (smol for minimal footprint, glommio for thread-per-core io_uring on Linux).

## Setting up tokio

```toml
[dependencies]
tokio = { version = "1", features = ["full"] }     # apps — kitchen sink
# tokio = { version = "1", features = ["macros", "rt-multi-thread", "net", "io-util", "time", "sync"] }  # libs — narrow
```

Entry point:

```rust
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // ...
    Ok(())
}

// Or, for tests:
#[tokio::test]
async fn it_works() { /* ... */ }

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn it_works_multithread() { /* ... */ }
```

`#[tokio::main]` is sugar for:

```rust
fn main() {
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async { /* ... */ });
}
```

The expanded form is useful when you need custom builder options (worker count, thread names, instrumentation hooks).

### Single-threaded vs multi-threaded

```rust
#[tokio::main(flavor = "current_thread")]   // single-threaded
#[tokio::main]                              // multi-threaded (default)
```

- **Single-threaded** (`current_thread`): no `Send` bound on spawned tasks (they all run on the same thread). Useful for CLIs, simple async tools, and anywhere you want absolute determinism. The "current" thread is whichever thread called `.block_on(...)`.
- **Multi-threaded** (default): a worker pool, tasks may move between threads. Required for any throughput-sensitive service. Spawned tasks must be `Send + 'static`.

## Tasks — `tokio::spawn` and `JoinSet`

`tokio::spawn` puts a future on the runtime to run independently:

```rust
let handle = tokio::spawn(async move {
    do_thing().await
});

// Later:
let result = handle.await?;     // joins; outer Result is JoinError (panic/cancel)
                                // inner is whatever do_thing returned
```

The `JoinHandle` returned by `spawn` is a future itself — awaiting it joins the task. Dropping the handle does **not** cancel the task; it runs to completion in the background. Use `handle.abort()` to cancel explicitly.

### `JoinSet` — structured groups of tasks

For more than two tasks, especially with dynamic fan-out, use `tokio::task::JoinSet`:

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();
for url in urls {
    set.spawn(async move { fetch(url).await });
}

while let Some(result) = set.join_next().await {
    match result {
        Ok(Ok(body)) => println!("got {} bytes", body.len()),
        Ok(Err(e)) => eprintln!("fetch failed: {e}"),
        Err(e) => eprintln!("task panicked: {e}"),
    }
}
```

What `JoinSet` gives you over `Vec<JoinHandle<_>>`:

- **Drop-on-abort.** Dropping the `JoinSet` aborts every still-running task — a partial structured-concurrency guarantee. (A full `tokio::task::scope` exists as a proposal but hasn't shipped as of May 2026.)
- **`join_next`** returns results as they complete, not in spawn order.
- **`shutdown()`** to cancel and await all in-flight tasks.

This is the canonical pattern for "spawn N async tasks and collect their results" in 2026.

### `tokio::join!` and `tokio::try_join!` — for a fixed small number

When the number of concurrent operations is **statically known and small**, use the macros:

```rust
let (users, posts, tags) = tokio::join!(
    fetch_users(),
    fetch_posts(),
    fetch_tags(),
);
// All three run concurrently; .join! awaits all.

let (users, posts) = tokio::try_join!(
    fetch_users(),       // returns Result<Vec<User>>
    fetch_posts(),       // returns Result<Vec<Post>>
)?;
// try_join! short-circuits — if any returns Err, the others are aborted.
```

Use `JoinSet` for dynamic fan-out; use `join!`/`try_join!` for fan-out where N is known and small (two to ~four operations).

### `select!` — race / pick the first

`tokio::select!` polls multiple futures concurrently and runs the branch for whichever completes first:

```rust
tokio::select! {
    result = client.recv() => {
        // got a message
    }
    _ = tokio::time::sleep(Duration::from_secs(30)) => {
        // timeout
    }
    _ = shutdown.cancelled() => {
        // graceful shutdown signaled
        return Ok(());
    }
}
```

Subtleties:

- **Branches are biased to top-down by default.** Use `select! { biased; ... }` to make this explicit, or `select!` with `#[tokio::main]` will give you a randomized poll order across branches.
- **Cancellation safety.** A branch not chosen has its future dropped *mid-`.await`*. If the underlying operation isn't cancel-safe (e.g., partially-written DB transaction), this is a bug. Read the [tokio docs on cancellation safety](https://docs.rs/tokio/latest/tokio/macro.select.html) before reaching for `select!`.

## Channels

Tokio offers four kinds of channels, plus a synchronous one from `std::sync::mpsc`. Pick by communication pattern:

| Channel | Senders | Receivers | When |
|---|---|---|---|
| `tokio::sync::mpsc::channel` | many | one | Most "send work to a task" patterns; bounded backpressure |
| `tokio::sync::mpsc::unbounded_channel` | many | one | Avoid — can grow without bound; only when memory pressure is bounded by upstream |
| `tokio::sync::oneshot::channel` | one | one | Reply channels — task receives a request with an oneshot Sender, sends the response back |
| `tokio::sync::broadcast::channel` | many | many | Pub-sub; every receiver gets every message; slow receivers can lag |
| `tokio::sync::watch::channel` | many | many | Latest-value semantics; receivers see only the most recent state (config reload, shutdown signal) |

### `mpsc` pattern

```rust
use tokio::sync::mpsc;

let (tx, mut rx) = mpsc::channel::<Job>(100);

tokio::spawn(async move {
    while let Some(job) = rx.recv().await {
        process(job).await;
    }
});

for job in jobs {
    tx.send(job).await?;          // backpressure — awaits if buffer full
}
drop(tx);                          // closes the channel; rx loop exits
```

Closing the channel: drop **all** senders, then the receiver's `.recv()` returns `None`. If you spawn many producer tasks, they each hold a `tx.clone()`; the channel only closes when every clone is dropped.

### `oneshot` for request/reply

```rust
let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
worker_tx.send(Job { data, reply: reply_tx }).await?;
let result = reply_rx.await?;
```

This is the standard "spawn a worker task and send it requests with embedded reply channels" pattern. The actor model in Rust looks exactly like this.

### `watch` for shared latest-value state

```rust
let (cfg_tx, mut cfg_rx) = tokio::sync::watch::channel(initial_config);

// Producer can update at any time:
cfg_tx.send(new_config)?;

// Consumer reads the latest:
let current = cfg_rx.borrow().clone();

// Or await changes:
loop {
    cfg_rx.changed().await?;
    let new = cfg_rx.borrow_and_update().clone();
    reload(&new);
}
```

`watch` is also the cleanest way to broadcast shutdown:

```rust
let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);
// In tasks: tokio::select! { _ = shutdown_rx.changed() => { ... }, ... }
// When done: shutdown_tx.send(true)?;
```

## Sync primitives in async — `tokio::sync::Mutex`/`RwLock`

`std::sync::Mutex` is fine **between** `.await`s — for guards held entirely inside a synchronous block, prefer the standard library Mutex (faster, no async overhead). The rule is **never hold a `std::sync::Mutex` guard across `.await`** — the task may be moved to another thread, leaving the lock orphaned, or other tasks waiting for the lock can deadlock the runtime.

```rust
// FINE — guard does not cross .await
let v = {
    let guard = state.lock().unwrap();
    guard.value
};
do_async_thing(v).await;

// BROKEN — guard crosses .await
let guard = state.lock().unwrap();
do_async_thing(guard.value).await;   // tokio may move the task to another thread here
```

When the guard *must* cross `.await`, use `tokio::sync::Mutex`:

```rust
use tokio::sync::Mutex;

let state = Arc::new(Mutex::new(State::default()));
let s = state.clone();
tokio::spawn(async move {
    let mut guard = s.lock().await;
    guard.value = compute().await;     // async work inside the lock
});
```

`tokio::sync::Mutex` is slower than `std::sync::Mutex` (it has to coordinate with the runtime). Use it only when needed; default to `std::sync::Mutex` (or `parking_lot::Mutex`) for short critical sections.

`tokio::sync::RwLock` is the same idea for many-readers/one-writer scenarios.

### Don't use channels just to share state

If two tasks both need to read+write a single value, a `Mutex` is often clearer than two channels. Channels shine for **pipelines** (A produces, B consumes) and **request/reply** (A asks B for something). For shared state, a lock is fine.

## Mixing sync and async — `spawn_blocking`

Calling a blocking API inside `async` *freezes the runtime worker* — the executor can't schedule other tasks until the blocking call returns. For CPU work or unavoidable blocking I/O, use `spawn_blocking`:

```rust
let result = tokio::task::spawn_blocking(move || {
    expensive_cpu_work(&data)
}).await?;
```

`spawn_blocking` moves the closure to a dedicated thread pool reserved for blocking work (default 512 threads). It returns a `JoinHandle` you `.await`.

For one-off "I have a blocking thing to do but I don't want to write a new function," `tokio::task::block_in_place`:

```rust
tokio::task::block_in_place(|| {
    // blocking work; current worker thread is taken offline,
    // tokio spins up a replacement
});
```

`block_in_place` only works on the multi-threaded runtime. For `current_thread`, always `spawn_blocking`.

When to use which:

- **A function that's blocking but rarely called:** `spawn_blocking` (one-shot, isolated).
- **A long CPU-bound section in an otherwise async function:** `spawn_blocking` returning the result.
- **Calling a blocking library from many places:** wrap it in a small async adapter using `spawn_blocking` internally.
- **You shouldn't be mixing them at all:** rewrite for async if a library has an async alternative.

## Cancellation

Cancellation in tokio is cooperative — a task only stops at `.await` points. Aborting a task drops its future, which runs the future's `Drop` impl. The two patterns:

### `JoinHandle::abort()` / `JoinSet` drop

```rust
let handle = tokio::spawn(work());
handle.abort();                       // sends abort; the task stops at next .await
let _ = handle.await;                 // get JoinError::is_cancelled() if you care
```

### `CancellationToken` (from `tokio-util`)

For cooperative graceful shutdown — many tasks listening for one cancel signal:

```toml
tokio-util = { version = "0.7", features = ["rt"] }
```

```rust
use tokio_util::sync::CancellationToken;

let cancel = CancellationToken::new();

let c = cancel.clone();
tokio::spawn(async move {
    tokio::select! {
        _ = c.cancelled() => {
            // graceful cleanup
        }
        _ = do_work() => {
            // completed normally
        }
    }
});

// Later, signal shutdown:
cancel.cancel();
```

`CancellationToken` supports child tokens — cancel a parent and every child also cancels:

```rust
let parent = CancellationToken::new();
let child = parent.child_token();
parent.cancel();     // child is also cancelled
```

Combined with `JoinSet`, this is the 2026 idiom for structured concurrent shutdown.

## Timeouts

```rust
use tokio::time::{timeout, Duration};

let result = timeout(Duration::from_secs(5), fetch(url)).await;
match result {
    Ok(Ok(body)) => println!("got {body}"),
    Ok(Err(e))   => eprintln!("fetch error: {e}"),
    Err(_)       => eprintln!("timed out"),
}
```

`timeout` returns `Result<T, Elapsed>`. The inner type is whatever the future returns.

For repeated operations, `tokio::time::interval`:

```rust
let mut ticker = tokio::time::interval(Duration::from_secs(60));
ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

loop {
    ticker.tick().await;
    do_periodic_work().await;
}
```

The default `MissedTickBehavior::Burst` will fire missed ticks all at once after a long pause — almost always wrong. Use `Skip` for "skip missed ticks" or `Delay` for "shift the schedule." Always set this explicitly.

## Streams

`Stream` is the async equivalent of `Iterator` — produces items asynchronously. Add `tokio-stream` for adapters:

```toml
tokio-stream = "0.1"
futures = "0.3"
```

```rust
use tokio_stream::StreamExt;

let mut stream = some_stream();
while let Some(item) = stream.next().await {
    process(item).await;
}
```

For collecting:

```rust
let items: Vec<_> = stream.collect().await;
```

For mapping/filtering concurrently with backpressure, use `futures::stream::StreamExt::buffer_unordered`:

```rust
use futures::stream::{self, StreamExt};

let results: Vec<_> = stream::iter(urls)
    .map(fetch)                      // returns a stream of futures
    .buffer_unordered(10)            // poll up to 10 at a time
    .collect()
    .await;
```

`buffer_unordered(N)` gives ordered-ish concurrency — up to N futures run at once, results yielded as they complete. This is the right shape when you have many independent async operations and want bounded concurrency.

## Threads — for blocking I/O and CPU work

`std::thread` is alive and well; reach for it when:

- The work is **blocking** and you'd rather not introduce an async runtime.
- The work is **CPU-bound** in a small, fixed-size pool.
- You need **OS-level isolation** (panics, signal handlers, real-time priority).

### `thread::spawn` and joining

```rust
let handle = std::thread::spawn(|| compute(42));
let result: i32 = handle.join().unwrap();
```

`join()` returns `thread::Result<T>` — `Err` only if the thread panicked. Unwrap is fine for "panics propagate to main."

### `thread::scope` (stable 1.63+) — borrow from the stack

The pre-1.63 pattern was "wrap shared data in `Arc` and clone for each thread." Scoped threads make local borrows work directly:

```rust
let data = vec![1, 2, 3, 4, 5];

let result = std::thread::scope(|s| {
    let h1 = s.spawn(|| data.iter().sum::<i32>());
    let h2 = s.spawn(|| data.iter().product::<i32>());
    (h1.join().unwrap(), h2.join().unwrap())
});
```

Threads spawned inside the scope can borrow from outside (including non-`'static` references). The scope guarantees all threads have joined before it exits. This is the right shape when you have a chunk of parallel work over local data.

### Channels — `std::sync::mpsc` and `crossbeam_channel`

For sync code, `std::sync::mpsc` is fine for simple producer-consumer. For richer needs (multi-consumer, select, bounded with timeout), use `crossbeam_channel`:

```toml
crossbeam-channel = "0.5"
```

```rust
let (tx, rx) = crossbeam_channel::bounded(100);
// Multiple consumers can all receive on rx (try_recv / recv).
// select! across multiple channels with crossbeam_channel::select!.
```

## CPU-bound parallelism — `rayon`

`rayon` is the answer for "I have a hot loop and want to parallelize it":

```toml
rayon = "1"
```

```rust
use rayon::prelude::*;

let sum: i64 = (0..1_000_000_i64).into_par_iter().sum();
let squares: Vec<i64> = items.par_iter().map(|x| x * x).collect();
items.par_sort_by_key(|x| x.score);
```

`rayon` uses work-stealing across a thread pool sized to the number of CPUs. The parallel iterator API mirrors `Iterator`, so most code converts by adding `par_` to the iterator method.

When `rayon` shines:

- **Data-parallel loops** — apply the same function to many elements.
- **Embarrassingly parallel work** — image processing, parsing many files, numerical computation.
- **Recursive divide-and-conquer** — `rayon::join(|| left(), || right())`.

When it doesn't:

- Tasks need to wait on I/O — that's async/tokio's job.
- Tasks need cross-task communication — channels via `crossbeam_channel` are clearer.
- The work is too cheap per task — overhead of the pool exceeds the win.

You can use `rayon` and `tokio` in the same program. The common shape: async for I/O, `tokio::task::spawn_blocking` wrapping a `rayon` parallel section for CPU work.

## `Send` and `Sync` — the auto-traits

- **`Send`**: a type is safe to *transfer* ownership across threads. (Almost everything is, except types with thread-local state like `Rc` and `RefCell`.)
- **`Sync`**: a type is safe to *share* (`&T`) across threads. `T: Sync` iff `&T: Send`.

These are auto-derived. The compiler figures out whether your type is `Send`/`Sync` from its fields. When it isn't:

```rust
// Compile error if you spawn this in tokio::spawn on a multi-thread runtime:
fn make() -> impl Future<Output = ()> {
    async {
        let rc = std::rc::Rc::new(42);    // Rc is !Send
        do_something().await;             // .await holds rc across the await — not Send
        println!("{}", *rc);
    }
}
```

Fix: use `Arc` instead of `Rc`, or scope the `Rc` so it doesn't cross `.await`.

### Common `!Send` types

- `Rc<T>` — not thread-safe refcount; use `Arc<T>`.
- `RefCell<T>`, `Cell<T>` — interior mutability without atomics; use `Mutex`/`RwLock`/`Atomic*`.
- Raw pointers in some cases.
- Anything containing one of the above transitively.

If your async function holds an `!Send` value across `.await`, the resulting future is `!Send`, and `tokio::spawn` (multi-thread) will reject it. Either rewrite to drop the `!Send` value before the await, or use `tokio::task::spawn_local` on a `LocalSet` (single-threaded execution).

## Choosing — a worked example

You need to fetch 100 URLs and parse each result, where parsing is CPU-bound:

- **Fetching is I/O-bound.** Tokio + reqwest + `JoinSet` or `buffer_unordered`.
- **Parsing is CPU-bound.** Send each fetched body to `spawn_blocking` (or a `rayon` parallel section).

```rust
use anyhow::Result;
use futures::stream::{self, StreamExt};

async fn fetch_and_parse(client: &reqwest::Client, url: &str) -> Result<Parsed> {
    let bytes = client.get(url).send().await?.bytes().await?.to_vec();
    let parsed = tokio::task::spawn_blocking(move || parse_blocking(&bytes)).await??;
    Ok(parsed)
}

async fn run(urls: Vec<String>) -> Vec<Result<Parsed>> {
    let client = reqwest::Client::new();
    stream::iter(urls)
        .map(|u| fetch_and_parse(&client, &u))
        .buffer_unordered(10)
        .collect()
        .await
}
```

This is the canonical shape: async for the I/O fan-out, `spawn_blocking` (or rayon) for the CPU section.

## Anti-patterns

| Don't | Do |
|---|---|
| Blocking syscall inside `async fn` (`std::fs::read`, `std::thread::sleep`) | Async equivalent (`tokio::fs::read`, `tokio::time::sleep`), or `spawn_blocking` for unavoidable blocking |
| `tokio::join!` / `try_join!` for dynamic fan-out | `JoinSet` |
| `Vec<JoinHandle<_>>` you await one at a time | `JoinSet::join_next` returns results as they complete |
| `std::sync::Mutex` guard held across `.await` | Scope the guard to a sync block, or use `tokio::sync::Mutex` |
| `Arc<Mutex<T>>` reflex for sharing state across tasks | One-owner task + channels (`mpsc` for messages, `oneshot` for replies) |
| `mpsc::unbounded_channel` | Bounded `mpsc::channel(N)` — bounded queues are backpressure; unbounded queues are memory leaks |
| Hand-rolled retry loops with `tokio::time::sleep` | `backon` crate for non-trivial retry logic |
| `tokio::time::interval` without `set_missed_tick_behavior` | Always set it — `Burst` (default) is almost always wrong |
| Calling `.unwrap()` on `JoinHandle::await` results | Handle `JoinError` — distinguishes panic from cancellation |
| `async-std`, `actix-rt`, custom runtimes | tokio unless you have a specific reason; async-std was discontinued in 2025 |
| `Rc<T>` in async code on the multi-threaded runtime | `Arc<T>` (or refactor to not need shared ownership) |
| Catching panics with `catch_unwind` around `.await` | Let panics propagate; the runtime handles them per-task |
| CPU-bound work inside `async fn` without `spawn_blocking` | Move it to `spawn_blocking` or a `rayon` parallel section |
| `lazy_static!` for a shared async resource (`reqwest::Client`, DB pool) | `LazyLock<Arc<Client>>` (one allocation, no macro) |
| One global `Arc<Mutex<Client>>` for an HTTP client | `reqwest::Client` is cheap to clone and internally pools connections — clone per task |
| Forgetting to drop `tx` to close an `mpsc` channel | Drop every clone of the sender; receivers see `None` only when all are dropped |
| Spawning a task and dropping its `JoinHandle` without `abort()` | Either await the handle, abort it, or use a `JoinSet` so drop cancels children |
| `task::block_in_place` from the `current_thread` runtime | `spawn_blocking` — `block_in_place` requires the multi-thread runtime |
