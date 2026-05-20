# Concurrency

Python has three concurrency tools and they are not interchangeable. Pick by what's blocking:

| Bottleneck | Pick | Why |
|---|---|---|
| I/O-bound, many connections (HTTP, DB, sockets) | **`asyncio`** | One event loop multiplexes thousands of waits cheaply |
| I/O-bound, blocking-only libraries (legacy DB drivers, requests) | **threads** (`ThreadPoolExecutor`) | GIL releases on syscalls, so threads work fine for I/O |
| CPU-bound work (numerics, parsing, crypto) | **processes** (`ProcessPoolExecutor`) | GIL serializes CPU work in threads; processes have separate interpreters |
| CPU-bound work, very hot path | C/Rust extension | Cython, PyO3, or a native binary called via subprocess |

The most common AI failure mode here is using `asyncio.gather` for new code (no structured cancellation), running CPU-bound work in threads (GIL serializes it), or putting blocking I/O calls inside async functions (freezes the event loop). All three corrupt otherwise-correct code in subtle ways.

## Modern asyncio (3.11+)

The post-3.11 asyncio is a much better language than the pre-3.11 version. Use the new tools:

### Entry point — `asyncio.run`

One top-level call per process. Do not call `asyncio.run()` from inside coroutines or libraries:

```python
import asyncio


async def main() -> None:
    ...


if __name__ == "__main__":
    asyncio.run(main())
```

### Task groups — structured concurrency (3.11+)

`TaskGroup` replaces `asyncio.gather` for new code. Children run concurrently, exceptions cancel siblings, and the group raises an `ExceptionGroup` if any child fails:

```python
import asyncio


async def fetch(client, url: str) -> bytes:
    r = await client.get(url)
    return r.content


async def main() -> None:
    async with httpx.AsyncClient() as client:
        async with asyncio.TaskGroup() as tg:
            t1 = tg.create_task(fetch(client, "https://a"))
            t2 = tg.create_task(fetch(client, "https://b"))
            t3 = tg.create_task(fetch(client, "https://c"))
        # All three complete; results in t1.result() etc.
        results = [t1.result(), t2.result(), t3.result()]
```

If `fetch` raises in one task, the others are cancelled automatically and `TaskGroup` re-raises wrapped in an `ExceptionGroup`. Handle with `except*`:

```python
try:
    await main()
except* httpx.HTTPError as eg:
    for err in eg.exceptions:
        logger.warning("fetch failed: %s", err)
except* ValueError as eg:
    ...
```

The "old" patterns are still legal but should not appear in new code:

| Don't | Do |
|---|---|
| `await asyncio.gather(*tasks)` | `async with asyncio.TaskGroup() as tg: ...` |
| `asyncio.wait_for(coro, 5)` | `async with asyncio.timeout(5): await coro` |
| Bare `loop = asyncio.new_event_loop()` | `asyncio.run(main())` |
| `asyncio.ensure_future` | `asyncio.create_task` or `tg.create_task` |
| Catch only the first exception | `try: ... except* T:` |

### Timeouts — `asyncio.timeout` (3.11+)

Replaces `asyncio.wait_for`. Cleaner block syntax, composable, returns a context manager you can introspect:

```python
async def main() -> None:
    async with asyncio.timeout(5.0):
        result = await long_running()
```

`asyncio.timeout_at(deadline)` if you have an absolute deadline. `cm.reschedule(new_deadline)` to extend the timeout mid-block.

A `TimeoutError` is raised at the `async with` exit (not at the awaited line) — wrap it where you can recover.

### Cancellation

The 3.11+ model is sound: cancellation is delivered as `asyncio.CancelledError` at the next await point. **Never swallow `CancelledError`** — propagate it:

```python
async def worker() -> None:
    try:
        await do_work()
    except asyncio.CancelledError:
        await cleanup()       # cleanup is fine
        raise                  # always re-raise
    except Exception:
        logger.exception("worker failed")
        raise
```

Catching `CancelledError` and continuing breaks structured concurrency. The only legitimate reason to suppress it is at the very edge of your program.

### Async context managers and iterators

Use them. `async with` for resources that need async setup/teardown; `async for` for streams:

```python
async def stream(url: str) -> None:
    async with httpx.AsyncClient() as client:
        async with client.stream("GET", url) as response:
            async for chunk in response.aiter_bytes():
                process(chunk)
```

For your own resources, write `__aenter__`/`__aexit__` or use `@asynccontextmanager`:

```python
from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(app):
    await app.startup()
    try:
        yield
    finally:
        await app.shutdown()
```

### Running blocking code from async

Never call blocking I/O directly inside an async function. Use `asyncio.to_thread` (3.9+):

```python
import asyncio


async def main() -> None:
    # subprocess.run, requests.get, file.read — anything blocking
    result = await asyncio.to_thread(blocking_call, arg1, arg2)
```

For a pool of threads under your control:

```python
import concurrent.futures
import asyncio


executor = concurrent.futures.ThreadPoolExecutor(max_workers=10)
loop = asyncio.get_running_loop()
result = await loop.run_in_executor(executor, blocking_call, arg)
```

For CPU-bound: use a `ProcessPoolExecutor` instead of threads (GIL):

```python
executor = concurrent.futures.ProcessPoolExecutor()
result = await loop.run_in_executor(executor, cpu_intensive, data)
```

### Common async pitfalls

- **Forgetting `await`.** `fetch(url)` returns a coroutine; you need `await fetch(url)`. Type checkers catch this if signatures are typed.
- **`time.sleep(5)` inside async.** Freezes the loop. Use `await asyncio.sleep(5)`.
- **`requests.get(...)` inside async.** Blocking; use `httpx.AsyncClient` instead.
- **CPU work inside async.** A long CPU loop blocks the loop. Offload via `to_thread` (releases the GIL on syscalls but not on pure-Python loops — for CPU-bound, use a process pool).
- **Mutating shared state without a lock.** `asyncio.Lock` for critical sections. The event loop is single-threaded, but `await` is a yield point — state can change between awaits.
- **`asyncio.run(main())` called from inside another async function.** It creates a new loop; nest with `await main()` instead.

## `anyio` — when to consider it

`anyio` is a structured-concurrency library that runs on both asyncio and trio. Use it if:

- You're writing a **library** that wants to be runtime-agnostic.
- You want richer task groups and primitives than stdlib offers.
- You're targeting trio specifically.

For application code that runs on asyncio, stdlib is fine. `anyio` adds a dependency and a small abstraction tax.

```python
import anyio


async def main() -> None:
    async with anyio.create_task_group() as tg:
        tg.start_soon(work, "a")
        tg.start_soon(work, "b")


anyio.run(main)   # runs on asyncio by default; pass backend="trio" to switch
```

FastAPI and HTTPX both use `anyio` under the hood, so it's already in your transitive deps.

## Threads — for blocking I/O only

`concurrent.futures.ThreadPoolExecutor` is the right tool when:

- The work blocks on I/O (file, socket, subprocess).
- You can't or won't rewrite for async.
- The library you're using isn't async-capable.

```python
import concurrent.futures
import httpx


def fetch(url: str) -> int:
    return httpx.get(url).status_code


urls = ["https://a", "https://b", "https://c"]
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
    results = list(pool.map(fetch, urls))
```

Patterns:

- Use `with` — the executor shuts down workers on exit.
- `max_workers` matters; default is fine for most cases, raise it for I/O-heavy work.
- `pool.map(fn, iter)` preserves order; `pool.submit(fn, ...)` + `as_completed` for unordered.
- Don't use threads for CPU-bound work — the GIL serializes Python bytecode execution.

### When threads break

- **CPU-bound code.** One thread is busy; the rest wait for the GIL.
- **Mutating shared state.** Use `threading.Lock`, `queue.Queue`, or atomic operations.
- **`fork()` after threads are started** — undefined behavior. Use the `spawn` start method for processes if mixing.

## Processes — for CPU-bound work

`concurrent.futures.ProcessPoolExecutor` runs each task in a separate Python interpreter. No GIL contention.

```python
import concurrent.futures


def heavy(data: bytes) -> bytes:
    # CPU-intensive: parsing, crypto, image processing, etc.
    return compute(data)


with concurrent.futures.ProcessPoolExecutor() as pool:
    results = list(pool.map(heavy, inputs))
```

Cost: starting processes is slow; the data crossing process boundaries is pickled. Each call is ~ms of overhead, so this is for chunky work — milliseconds-or-more per call, not microseconds.

For shared memory between processes, use `multiprocessing.shared_memory` (3.8+) or `multiprocessing.Manager` for higher-level shared objects.

## Free-threaded (no-GIL) Python — watch, don't bet

Python 3.13 shipped free-threading as experimental; 3.14 promotes it to officially supported (PEP 779). The single-threaded penalty has dropped from 20–40% to 5–10%.

**Status for 2026:**

- Test against it if your project does CPU-bound parallelism — it's the future.
- Don't ship on it as your only build. Many C extensions (numpy, pillow, cryptography, etc.) still lack free-threaded wheels.
- The free-threaded build and the JIT are mutually exclusive. Pick one.
- Default likely lands in 3.16 or 3.17 (2027–2028).

How to try it:

```bash
uv python install 3.13.0t        # the `t` suffix is the free-threaded build
uv venv --python 3.13t
```

Code that already uses processes for CPU work doesn't need changes when free-threading lands — it just gets the option to switch to threads later.

## Choosing — a worked example

You need to fetch 100 URLs and parse each result.

- **Fetching is I/O-bound.** `asyncio` + `httpx.AsyncClient` + `TaskGroup`.
- **Parsing is fast (microseconds, pure Python).** Just do it in the same async task.
- **Parsing is slow (CPU-bound, milliseconds).** Hand parsed bodies off to a `ProcessPoolExecutor` via `loop.run_in_executor`.

```python
import asyncio
import concurrent.futures
import httpx


def heavy_parse(data: bytes) -> dict:
    # CPU-bound parsing
    return ...


async def fetch_and_parse(client, executor, url: str) -> dict:
    r = await client.get(url)
    r.raise_for_status()
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(executor, heavy_parse, r.content)


async def main(urls: list[str]) -> list[dict]:
    async with httpx.AsyncClient() as client:
        with concurrent.futures.ProcessPoolExecutor() as pool:
            async with asyncio.TaskGroup() as tg:
                tasks = [tg.create_task(fetch_and_parse(client, pool, u)) for u in urls]
        return [t.result() for t in tasks]
```

This is the canonical shape: async for I/O, processes for CPU.

## Anti-patterns

- **`asyncio.gather(*tasks)` in new 3.11+ code.** Use `TaskGroup`.
- **`asyncio.wait_for(coro, 5)`.** Use `async with asyncio.timeout(5)`.
- **`time.sleep(...)` in async functions.** Always `await asyncio.sleep(...)`.
- **`requests.get(...)` in async.** Use `httpx.AsyncClient`.
- **CPU-bound work in threads.** GIL. Use processes.
- **Catching `CancelledError` and not re-raising.** Breaks structured concurrency.
- **Calling `asyncio.run(main())` from inside another coroutine.** Just `await main()`.
- **Forgetting `await`.** `coro = fetch(url)` does nothing; needs `await fetch(url)`.
- **Sharing mutable state across coroutines without a lock.** Even single-threaded asyncio yields at every `await`.
- **Using `multiprocessing` directly when `concurrent.futures.ProcessPoolExecutor` would do.** The latter is the higher-level, friendlier API.
- **Forking after threads have started.** Undefined behavior on Linux; use `spawn` start method.
