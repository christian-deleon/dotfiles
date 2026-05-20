---
name: python
description: Modern Python (3.12+) for both small scripts and real applications — language idioms, packaging, type hints, async, web services, data models, testing. ALWAYS use when editing `*.py`/`*.pyi`/`pyproject.toml`/`uv.lock`/`requirements*.txt`/`Pipfile`/`setup.cfg`/`tox.ini`, files under `src/` or `tests/` in a Python project, or for prompts mentioning Python, scripts, FastAPI, Django, Starlette, asyncio, type hints, dataclass, Pydantic, msgspec, ruff, mypy, pyright, pytest, uv, `pip install`, `pyproject`, or 'write a script', 'add an endpoint', 'fix this type error', 'parse these args', 'add a test'. Opinionated stack — uv for env/deps, ruff for lint/format, pyright as primary type checker (mypy for libraries), pytest, FastAPI for new APIs, httpx, pydantic-settings, structlog. Examples target Python 3.12+.
compatibility: opencode
---

# Python

Python is two languages in one suit. As a *scripting language* it's a typed bash-replacement — single files, glue between programs, PEP 723 inline metadata, run via `uv run`. As an *application language* it's a strict, statically-checked, packaged ecosystem with lockfiles, type checkers, async runtimes, ASGI servers, and a fully-formed `src/` layout. This skill covers both, with the same opinions throughout.

The most common AI failure mode here is writing 2015-era Python: `setup.py`, `requests`, `Optional[X]`, `os.path.join`, `except Exception` swallowed silently, untyped public functions, mutable default args, `print()` for logs in libraries, and `pip install` directly into a global env. Don't do any of that. The defaults below are non-negotiable for new code.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Set up a project, add deps, configure ruff/pyright/pytest | [tooling.md](tooling.md) |
| Author `pyproject.toml`, pick a build backend, ship a CLI/library, write a single-file `uv run` script | [packaging.md](packaging.md) |
| Add type hints, fix `mypy`/`pyright` errors, use PEP 695 / `Protocol` / `TypeIs` | [types.md](types.md) |
| Pick between `dataclass`, `attrs`, Pydantic, `msgspec`, `TypedDict` | [data-models.md](data-models.md) |
| Write `async` code, use `TaskGroup`, choose threads vs processes vs async | [concurrency.md](concurrency.md) |
| Build an API, pick a web framework, configure logging, make HTTP calls | [web.md](web.md) |

For one-off edits, the cheat sheets below are usually enough. Reach for the reference files when the task warrants depth.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Python version | **3.12+** | 3.13/3.14 OK; targets older only with explicit reason |
| Env / deps | **`uv`** | Replaces pip + pip-tools + pipx + virtualenv + pyenv |
| Lint + format | **`ruff check` + `ruff format`** | Replaces flake8, isort, black, pyupgrade, most pylint |
| Type checker | **`pyright`** (apps) / **`mypy`** (libraries) | Pyright is faster + ships with Pylance; mypy is the lingua franca for distributed libs |
| Test runner | **`pytest`** | Plus `pytest-cov`, `pytest-asyncio`, `hypothesis` where useful |
| Models at I/O boundaries | **Pydantic v2** | Internal data → `@dataclass(slots=True)`; high-perf serialization → `msgspec` |
| HTTP client | **`httpx`** | Sync + async API, HTTP/2; never `requests` in new code |
| Web framework | **FastAPI** for new APIs | Django for full-stack + ORM; Starlette when you want ASGI primitives bare |
| CLI framework | **`typer`** for typed CLIs | `click` for plugin-heavy; `argparse` only when no deps allowed |
| Config | **`pydantic-settings`** | Env-first; `.env` for local dev only |
| Logging | stdlib `logging.getLogger(__name__)` in libs, **`structlog`** in services | Never `print()` in library code |

## Header / preamble

A script that ships in a project:

```python
"""Brief one-line description.

Longer notes here if useful. PEP 257 docstring conventions.
"""
from __future__ import annotations  # not needed in 3.14+, helpful in 3.12/3.13

import logging
from pathlib import Path

logger = logging.getLogger(__name__)


def main() -> int:
    ...
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

A one-off self-contained script — **prefer this over an ad-hoc project** for anything throwaway. PEP 723 + `uv run script.py` and there is no project to maintain:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx", "rich"]
# ///
"""Fetch X and print Y."""
import httpx
from rich import print

print(httpx.get("https://example.com").status_code)
```

See [packaging.md](packaging.md) for the full scripts-vs-app spectrum.

## Modern syntax cheat sheet (3.12+)

| Use | Don't use |
|---|---|
| `X \| None` (PEP 604) | `Optional[X]`, `Union[X, None]` |
| `list[int]`, `dict[str, int]` | `typing.List`, `typing.Dict` |
| `def f[T](xs: list[T]) -> T:` (PEP 695) | `T = TypeVar("T")` + `def f(xs: list[T])` in new 3.12+ code |
| `type Result[T] = T \| None` (PEP 695) | `Result: TypeAlias = T \| None` |
| `match value: case ...:` for tagged-union dispatch | long `if isinstance(...) elif isinstance(...)` chains |
| `f"{user=}"` for debug | `f"user={user}"` |
| `if (n := len(data)) > 10:` (walrus) | computing the same value twice |
| `async with asyncio.TaskGroup() as tg: tg.create_task(...)` | bare `asyncio.gather(...)` for new 3.11+ code |
| `async with asyncio.timeout(5):` | `asyncio.wait_for(..., 5)` |
| `try: ... except* ValueError:` for grouped failures | catching only the first exception from concurrent code |
| `tomllib.loads(text)` (stdlib) | adding `tomli`/`toml` dep |
| `enum.StrEnum`, `enum.IntEnum` | hand-rolled string constants |
| `pathlib.Path("x") / "y" / "z.txt"` | `os.path.join("x", "y", "z.txt")` |
| `subprocess.run(["cmd", arg], check=True)` | `subprocess.run("cmd " + arg, shell=True)` |
| `secrets.token_urlsafe(32)` for tokens | `random.choice(...)` for anything security-related |
| `is None` / `is not None` | `== None` / `!= None` |

## Error handling

```python
class AppError(Exception):
    """Root for everything this app raises."""


class ConfigError(AppError):
    """Bad or missing configuration."""


def load_config(path: Path) -> Config:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as e:
        raise ConfigError(f"config not found at {path}") from e
    try:
        return Config.model_validate_json(text)
    except ValueError as e:
        raise ConfigError(f"invalid config at {path}") from e
```

Rules:

- **Custom hierarchy rooted at one base** (`AppError`). Callers `except AppError`, never `except Exception`.
- **Never bare `except:`** — it catches `KeyboardInterrupt` and `SystemExit`. Almost never bare `except Exception:` either; if you do, re-raise or log + escalate at a single top-level boundary.
- **`raise … from e`** preserves the cause. Use `from None` deliberately when chaining would leak detail.
- **Context managers for all resources**: `with open(...)`, `with httpx.Client() as client:`, `contextlib.ExitStack` for variable counts, `contextlib.suppress(FileNotFoundError)` for "I expect this to maybe fail."
- **Exception groups** (`try/except*`) for concurrent code that can fail in multiple ways at once — required when working with `asyncio.TaskGroup`. See [concurrency.md](concurrency.md).
- **Never use `assert` for runtime checks** — `python -O` strips them. Use `if not x: raise ValueError(...)`.

## Stdlib reflexes worth knowing

| Use | Instead of |
|---|---|
| `pathlib.Path` | `os.path` for new code |
| `tomllib.loads(text)` (3.11+) | external `tomli` |
| `zoneinfo.ZoneInfo("UTC")` | `pytz` |
| `secrets.token_urlsafe(n)`, `secrets.compare_digest(...)` | `random`, `==` for token compare |
| `functools.cache` (unbounded), `functools.lru_cache(maxsize=N)`, `functools.cached_property` | hand-rolled memoization |
| `enum.StrEnum` / `enum.IntEnum` (3.11+) | string constants |
| `subprocess.run(args, check=True, text=True)` | `os.system`, `shell=True` on untrusted input |
| `shlex.join`, `shlex.quote` | hand-rolled shell string assembly |
| `dataclasses.dataclass(slots=True)` | hand-rolled `__init__`/`__repr__` |
| `contextlib.contextmanager`, `ExitStack`, `suppress`, `chdir` (3.11+) | hand-rolled try/finally |
| `logging.getLogger(__name__)` | `print()` in library/module code |
| `tempfile.TemporaryDirectory`, `NamedTemporaryFile` | hardcoded `/tmp/...` |
| `open(path, encoding="utf-8")` | bare `open(path)` (locale-dependent) |

## Universal rules

These apply across both scripts and applications:

1. **Type hints on every public function and method.** Internal helpers can skip them if the types are obvious from context; public APIs cannot.
2. **`pathlib` for paths.** Never `os.path.join`, never raw string concatenation. New code only uses `os.path` for the handful of things `pathlib` doesn't cover.
3. **`pydantic` (or `msgspec`) at every I/O boundary** — HTTP requests/responses, config files, environment variables, JSON files, message queues. Internal data carriers stay as `@dataclass`. See [data-models.md](data-models.md).
4. **Never mutate function arguments.** If you need to return a modified copy, return a copy. Mutable default args (`def f(x=[]):`) are a bug — use `None` and `x = x or []`.
5. **No `print()` in library code.** Use `logging.getLogger(__name__)`. CLIs may print to stdout for their actual output, but logs go to stderr via `logging` (or `structlog`).
6. **`subprocess.run(args_list, check=True)`** — argument list, never a single shell string, never `shell=True` on untrusted input.
7. **`with` for all file I/O.** No bare `open(...)` without a context manager; file handles leak.
8. **`is None` / `is not None`** for None checks. `== None` is wrong (and many type checkers will flag it).
9. **`from __future__ import annotations`** at the top of every file in 3.10–3.13 codebases — makes annotations lazy and stops circular-import nonsense. Unnecessary in 3.14+ but harmless.
10. **Configure logging once at app startup**, never in libraries. See [web.md](web.md) for `dictConfig` patterns.

## When Python isn't the right tool

Switch languages when you hit any of:

- A hot loop where the inner work is microseconds and there are millions of iterations — Cython, Rust+PyO3, or just write the hot function in another language and call it via `subprocess` or FFI.
- A binary that needs to ship without a Python runtime → Go or Rust.
- Strict latency budgets for high-fanout services → Go or Rust will usually be a better fit than tuning Python.
- Long-running CPU-bound parallelism on default CPython today — the GIL is still real. Use processes (`concurrent.futures.ProcessPoolExecutor`) or wait for the free-threaded build to mature.

Python is great at: I/O-bound services, ML/data tooling, CLIs, glue, prototypes that ship, and anything where developer time matters more than CPU time.

## Don't / Do

| Don't | Do |
|---|---|
| `def f(x=[]):` (mutable default) | `def f(x: list \| None = None): x = x or []` |
| `except:` or `except Exception:` swallowed | typed `except SpecificError:` or re-raise; one top-level boundary catches `Exception` and exits |
| `os.path.join(a, b)` | `Path(a) / b` |
| `requests.get(...)` in new code | `httpx.get(...)` (or `async with httpx.AsyncClient()`) |
| `setup.py` for new projects | `pyproject.toml` (PEP 621) + a build backend |
| `print(f"loaded {n}")` in a library | `logger.info("loaded %d", n)` |
| `pip install X` outside a venv | `uv add X` in a project, or PEP 723 inline metadata + `uv run` |
| `open("data.txt")` no `with`, no `encoding=` | `with open("data.txt", encoding="utf-8") as f:` |
| `time.sleep(5)` polling loop | event/future/callback, or `async` with `asyncio.timeout` |
| `if x == None:` | `if x is None:` |
| `Optional[X]`, `Union[X, Y]` | `X \| None`, `X \| Y` |
| `typing.List[int]`, `typing.Dict[str, int]` | `list[int]`, `dict[str, int]` |
| `T = TypeVar("T")` everywhere in 3.12+ | `def f[T](xs: list[T]) -> T:` (PEP 695) |
| `asyncio.gather(...)` for new code | `async with asyncio.TaskGroup() as tg: tg.create_task(...)` |
| Threads for CPU-bound work | `ProcessPoolExecutor` (or rewrite hot path in Rust) |
| `assert` for runtime checks | `if not x: raise ValueError(...)` |
| `random.choice` for tokens/passwords | `secrets.token_urlsafe(n)`, `secrets.choice(...)` |
| `subprocess.run(f"cmd {arg}", shell=True)` | `subprocess.run(["cmd", arg], check=True)` |
| `from module import *` in libraries | explicit names; or `__all__` if you must |
| `global x` for shared mutable state | a class, dataclass, or dependency-injected container |
| `json.loads(text)["key"]["nested"]` raw | `Model.model_validate_json(text)` (Pydantic) at the boundary |
| Mutating function arguments | return a new value; document any in-place ops loudly |
| Hardcoded `/tmp/foo.json` | `tempfile.NamedTemporaryFile`, `tempfile.TemporaryDirectory` |
| Hand-rolled venv juggling, `pyenv install`, `pip install -r` dance | `uv sync`, `uv add`, `uv run` |
| Untyped public function signatures | type-hint every param and return value on public APIs |
| `# type: ignore` with no error code | `# type: ignore[arg-type]  # reason: …` |
| `class C: pass` then `c.x = 1; c.y = 2` | `@dataclass(slots=True) class C: x: int; y: int` |

## After you change anything in this skill

Run `dot install` to refresh the symlinks across all three tools. No restart needed.
