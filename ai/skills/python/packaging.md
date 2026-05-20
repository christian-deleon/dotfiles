# Packaging & Project Layout

Python packaging finally consolidated. There is one source of truth (`pyproject.toml`, PEP 621), one canonical layout (`src/`), and a small set of build backends that all read from the same place. `setup.py` and `setup.cfg` should not exist in new projects.

The scripts-vs-app spectrum is now a continuum. Start with a single `.py` and PEP 723 inline metadata; promote to a project only when the script grows beyond one file or earns multiple users.

## The scripts → app spectrum

| Stage | What it looks like | Use when |
|---|---|---|
| **One-off script** | `script.py` with PEP 723 metadata, `uv run script.py` | Throwaway, single-file, occasional reuse |
| **Shared CLI tool** | Same script, installed globally via `uv tool install <git-url>` or `uvx <pkg>` | Multiple users; still one file |
| **Project** | `pyproject.toml` + `src/<pkg>/` + lockfile | Multi-file, tests, deps that need to be locked |
| **Library** | Same plus `py.typed`, build backend, CI publishing | Distributed via PyPI or internal index |

**Default to the lowest stage that works.** A 50-line one-shot ETL should not have a `pyproject.toml`.

## PEP 723 — single-file scripts

The metadata is a comment block parsed by `uv` (and any PEP 723-aware runner):

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "httpx>=0.27",
#     "rich>=13",
# ]
# ///
"""Fetch a URL and pretty-print the response."""
import sys
import httpx
from rich import print

def main(url: str) -> int:
    r = httpx.get(url, timeout=10.0)
    r.raise_for_status()
    print(r.json())
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
```

`chmod +x` and run directly. `uv` creates an ephemeral environment, installs the deps, and runs the script. Subsequent runs hit the cache.

`uv add --script script.py httpx` will update the inline metadata block for you.

## `pyproject.toml` (PEP 621)

The complete shape of a modern `pyproject.toml`:

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "my-app"
version = "0.1.0"
description = "One-sentence description."
readme = "README.md"
requires-python = ">=3.12"
license = "MIT"
authors = [{ name = "Christian De Leon", email = "..." }]
keywords = ["foo", "bar"]
classifiers = [
    "Development Status :: 3 - Alpha",
    "Programming Language :: Python :: 3.12",
    "Programming Language :: Python :: 3.13",
]
dependencies = [
    "httpx>=0.27",
    "pydantic>=2.5",
]

[project.optional-dependencies]
cli = ["typer>=0.12", "rich>=13"]
postgres = ["asyncpg>=0.29"]

[project.scripts]
my-cli = "my_app.cli:main"          # creates an installed `my-cli` command

[project.urls]
Homepage = "https://example.com"
Repository = "https://github.com/me/my-app"

[dependency-groups]    # PEP 735 — dev/test/docs deps; not user-facing
dev = [
    "pytest>=8",
    "pytest-cov",
    "ruff>=0.7",
    "pyright>=1.1.380",
]
docs = ["mkdocs-material"]

[tool.uv]
default-groups = ["dev"]            # `uv sync` includes dev by default

[tool.hatch.build.targets.wheel]
packages = ["src/my_app"]
```

Key points:

- **`[project]` is the standard.** No `[tool.poetry]`, no `[tool.setuptools.metadata]`, no `setup.cfg`.
- **`[project.optional-dependencies]`** is for *user-facing extras* — `pip install my-app[cli]`. **`[dependency-groups]`** (PEP 735) is for *developer-facing* deps — dev, test, docs. They are different.
- **`requires-python`** is enforced by `pip`/`uv` at install time. Set it explicitly.
- **`license = "MIT"`** is the PEP 639 string form (preferred). The old `license = { text = "MIT" }` table form still parses.
- **`[project.scripts]`** entries create installed CLI commands. The value is `module.path:function`. The function takes no arguments and returns an int exit code (or raises `SystemExit`).
- **`[tool.<name>]`** tables are tool-specific config. Each tool reads its own table; unknown tables are ignored.

## `src/` layout

```
my-app/
├── pyproject.toml
├── README.md
├── uv.lock                     # commit this
├── .python-version             # commit this; tells uv which version to use
├── src/
│   └── my_app/
│       ├── __init__.py         # `__version__` lives here
│       ├── __main__.py         # `python -m my_app` enters here
│       ├── cli.py              # `main()` for the [project.scripts] entry
│       └── ...
└── tests/
    ├── conftest.py
    └── test_*.py
```

Why `src/`:

- **Tests run against the installed package**, not the working copy. Forgotten `__init__.py`, missing `MANIFEST.in`, missing package_data — all show up immediately instead of at `pip install` time.
- **No accidental imports** of the project from the project root (`python -c "import my_app"` only works when installed).
- **Tooling defaults assume it.** `uv init` scaffolds `src/`. Ruff, pyright, pytest all autodiscover it.

Flat layout (`my_app/` next to `pyproject.toml`, no `src/`) is fine for **truly small** scripts that became one-module packages. Don't reach for it in a multi-module project.

### `__init__.py`

- **Required** for regular packages. Even if empty.
- **`__version__`** convention: declare it in `src/my_app/__init__.py` as a string, or use `importlib.metadata.version("my-app")` to read it from the installed metadata. The latter avoids the "version in two places" trap.
- **Don't put logic in `__init__.py`** beyond re-exports and `__version__`. Heavy imports here slow every `import my_app`.

### `__main__.py`

Makes `python -m my_app` work. Common pattern:

```python
# src/my_app/__main__.py
from my_app.cli import main

raise SystemExit(main())
```

## Build backends

| Backend | Use when |
|---|---|
| **`hatchling`** | Default for new pure-Python projects. Most popular, fewest opinions, well-documented. |
| **`uv_build`** | Astral's own backend. Fast, pairs naturally with `uv`. Newer; ecosystem support still maturing. |
| **`setuptools`** | C extensions, Cython, legacy projects. |
| **`flit-core`** | Single-file pure-Python packages with no config. Minimalist. |
| **`poetry-core`** | Projects already committed to Poetry. New work: pick something else. |
| **`pdm-backend`** | PDM users. Standards-compliant; niche. |

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

That's the whole answer for most projects.

### Hatchling specifics

Hatchling auto-discovers `src/<pkg>/` by name match. Override only when needed:

```toml
[tool.hatch.build.targets.wheel]
packages = ["src/my_app"]

[tool.hatch.build.targets.sdist]
include = ["src/", "tests/", "README.md", "pyproject.toml"]
```

Dynamic version from the package:

```toml
[project]
name = "my-app"
dynamic = ["version"]

[tool.hatch.version]
path = "src/my_app/__init__.py"
```

## Building and publishing

```bash
uv build                         # writes dist/*.whl and dist/*.tar.gz
uv publish                       # uploads to PyPI (uses ~/.pypirc or UV_PUBLISH_TOKEN)
uv publish --index testpypi      # uploads to test.pypi.org
```

For internal indexes:

```toml
[[tool.uv.index]]
name = "internal"
url = "https://pypi.internal.example.com/simple/"
default = true
```

## Library-specific concerns

If you're shipping a library to PyPI:

1. **Add `py.typed`** (empty marker file) inside the package: `src/my_lib/py.typed`. This is PEP 561 — tells type checkers the package ships type information. Without it, `mypy` and `pyright` will see your library as untyped.
2. **Declare it as package data** if hatchling doesn't pick it up automatically (it usually does):
   ```toml
   [tool.hatch.build.targets.wheel.force-include]
   "src/my_lib/py.typed" = "my_lib/py.typed"
   ```
3. **Use the broadest `requires-python` you actually support.** A library that requires-python = ">=3.13" excludes most users; aim for "current stable - 2" unless you have a reason.
4. **Don't pin runtime deps tightly.** Apps pin (`==`); libraries use ranges (`>=2,<3`). Tight pins in libraries create resolver hell for users.
5. **Run pyright AND mypy in CI.** Pyright catches more inference issues, mypy is what most downstream users will run.

## Versioning

- **SemVer** is the default expectation: MAJOR.MINOR.PATCH. Pre-1.0 means anything can change; once you cut 1.0 you owe consumers stability on minor releases.
- **CalVer** for apps and tools (e.g. `2026.5.19`). Don't bother with SemVer for an internal service.
- **Read the version from package metadata**, not a hardcoded string in `setup.py`-style. `importlib.metadata.version(__package__)` works at runtime; `[tool.hatch.version.path]` works at build time.

## Containers — distroless with `uv`

For services that ship as container images, the 2026 standard is **`gcr.io/distroless/python3-debian12:nonroot`** with the venv populated by `uv` in a builder stage and copied across with `COPY --link`. Modern BuildKit shape — cache mounts, multi-platform-friendly, no shell in the runtime:

```dockerfile
# syntax=docker/dockerfile:1
ARG PYTHON_VERSION=3.13
ARG BASE=gcr.io/distroless/python3-debian12:nonroot

FROM ghcr.io/astral-sh/uv:0.5-python${PYTHON_VERSION}-bookworm-slim AS build
ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/venv
WORKDIR /src

# Resolve deps only — cached against uv.lock + pyproject.toml
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# Install the project itself
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=.,target=/src \
    uv sync --frozen --no-dev --no-editable

FROM ${BASE}
COPY --link --from=build /venv /venv
ENV PATH=/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
USER 65532:65532
EXPOSE 8000
ENTRYPOINT ["/venv/bin/python", "-m", "my_pkg"]
```

Why each piece:

- **`# syntax=docker/dockerfile:1`** — pins the BuildKit frontend independent of the Docker engine.
- **`ghcr.io/astral-sh/uv:0.5-python<X>-bookworm-slim`** — official `uv` image with the matching Python; saves an `apt install python3` round-trip.
- **`UV_LINK_MODE=copy`** — copy files into the venv rather than hardlinking; required when the cache mount and venv are on different filesystems.
- **`UV_COMPILE_BYTECODE=1`** — precompile `.pyc` at install time; eliminates the cold-start cost of first import.
- **`UV_PYTHON_DOWNLOADS=never`** — never let uv silently pull a different Python at runtime; the base image's Python is authoritative.
- **Two-step `uv sync`** — deps first (cached against `uv.lock` only), project second. Changes to `pyproject.toml` extras don't rebust the deps cache.
- **`--no-dev --no-editable`** — production install: no dev deps, no editable installs.
- **`--mount=type=cache,target=/root/.cache/uv`** — uv's content-addressed cache persists across builds.
- **`--mount=type=bind,source=uv.lock,target=uv.lock`** — read the lockfile without copying it into a layer.
- **`COPY --link --from=build /venv /venv`** — independent layer that survives base-image rebases. Runtime python finds the venv via `PATH=/venv/bin:$PATH`.
- **`gcr.io/distroless/python3-debian12:nonroot`** — Python runtime, no shell, no pip, runs as UID 65532. Drastically smaller attack surface.

For C-extension wheels that need glibc (numpy, pandas, scipy, cryptography) — distroless `python3` is glibc-based, so `pip install pandas` works. If you reach for Alpine instead, pip will silently rebuild wheels from source for hours; **stay on distroless or debian-slim.**

If the app shells out to system tools (`git`, `ffmpeg`) or needs a healthcheck binary like `wget`/`curl`, switch the final stage to `python:3.13-slim` and create a non-root user explicitly:

```dockerfile
FROM python:3.13-slim AS runtime
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    groupadd -r -g 65532 nonroot && \
    useradd -r -u 65532 -g 65532 -s /sbin/nologin nonroot
COPY --link --from=build /venv /venv
ENV PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1
USER 65532:65532
ENTRYPOINT ["python", "-m", "my_pkg"]
```

Build it multi-platform via QEMU (Python doesn't cross-compile cleanly — wheels are arch-specific):

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  --tag ghcr.io/acme/api:v1.2.3 --push .
```

For Compose, multi-target builds via `bake`, image signing (cosign), SBOM/provenance attestations, and admission verification (Kyverno `verifyImages`) — see the [`docker`](../docker/SKILL.md) skill.

## What not to do

- **No `setup.py`** in new projects. `pyproject.toml` does everything `setup.py` did.
- **No `setup.cfg`** for new projects either.
- **No `requirements.txt`** as the source of truth. `pyproject.toml` is. Generate `requirements.txt` from the lock with `uv export --no-hashes > requirements.txt` if a downstream tool needs it.
- **No `MANIFEST.in`** unless you specifically need sdist file inclusion that the backend doesn't auto-detect. Hatchling almost always auto-detects.
- **No version bumping by hand in three places.** Pick one source (the package's `__init__.py`, or the project metadata) and have the others read from it.
- **No `Pipfile` / `Pipfile.lock`** for new work — pipenv has lost momentum. `uv.lock` is the modern equivalent.
