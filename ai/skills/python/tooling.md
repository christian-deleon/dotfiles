# Tooling

Python's tooling story consolidated hard in 2024–2026. The default stack is `uv` + `ruff` + `pyright`/`mypy` + `pytest`. Most older choices (pip, pip-tools, pipx, virtualenv, pyenv, flake8, isort, black, pyupgrade) are now subsumed by one of these or are legacy. Use the alternatives only when there's a concrete reason.

## `uv` — environment, dependencies, lockfile, Python versions

`uv` replaces six tools in one binary and runs 10–100× faster. Use it for everything: installing Python, creating venvs, adding/removing deps, locking, running scripts, running CLIs, publishing.

### Project lifecycle

```bash
uv init my-app                  # Scaffold a new project (pyproject.toml + src/ + .python-version)
uv init --lib my-lib            # Library scaffolding (different defaults)
uv init --script tool.py        # PEP 723 single-file script with inline metadata

uv python install 3.12          # Install a Python toolchain (managed in ~/.local/share/uv/)
uv python pin 3.12              # Write .python-version

uv add httpx 'pydantic>=2'      # Add runtime deps; updates pyproject.toml + uv.lock
uv add --dev pytest ruff mypy   # Add to the [dependency-groups].dev group
uv add --optional cli typer     # Add to the [project.optional-dependencies].cli extra
uv remove requests              # Remove

uv sync                         # Resolve + install exactly what the lockfile says
uv sync --frozen                # Like sync, but fail if lockfile would change
uv lock                         # Just regenerate the lockfile, don't install
uv lock --upgrade-package httpx # Upgrade a single dep
uv lock --upgrade               # Upgrade everything within version constraints

uv run pytest                   # Run a command inside the project's env
uv run -- python -c "..."       # `--` ends uv flags; useful when the command takes its own
uv run --with rich script.py    # Add ephemeral deps for one run

uv tool install ruff            # Install a CLI globally (was: pipx install)
uvx ruff check                  # One-shot run without installing (was: pipx run)
```

### Single-file scripts (PEP 723)

`uv` shines for one-off scripts. No project, no venv juggling:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx", "rich"]
# ///
import httpx
from rich import print
print(httpx.get("https://example.com").status_code)
```

`chmod +x` and run it directly, or `uv run script.py`. See [packaging.md](packaging.md) for the scripts-vs-app spectrum.

### Workspaces (monorepos)

`uv` natively supports workspaces — multiple packages sharing one lockfile. The root `pyproject.toml`:

```toml
[tool.uv.workspace]
members = ["packages/*"]
```

Each member gets its own `pyproject.toml`. `uv sync` resolves the entire workspace.

### Sharp edges

- `uv pip install …` works for `pip`-style commands but **bypasses the lockfile**. Prefer `uv add` / `uv sync` for project work.
- `uv.lock` is **`uv`-specific** today. PEP 751 (`pylock.toml`) is the future universal format, but adoption is partial as of 2026. `uv` can export to `pylock.toml` (`uv export --format pylock`) — useful for tooling that doesn't speak `uv.lock`.
- The first `uv sync` in a repo creates `.venv/` in the project root. Don't commit it; `uv` puts it there for editor/IDE convenience.

### When the alternatives still fit

- **Poetry** — fine for libraries already invested in it. Migration friction is real; don't churn working projects. New work → `uv`.
- **PDM** — niche; standards-purists who specifically want the PDM-backend and PEP 751 lockfile today.
- **Hatch** — strong for matrix testing (multi-Python, multi-env library matrices). Pair with `uv` or use standalone.
- **pip-tools** — fine for pip-only orgs. `uv pip compile` is a faster drop-in replacement.
- **Conda / Mamba** — when you need non-Python deps (CUDA, system libs) bundled.

## `ruff` — lint + format

`ruff check` replaces flake8, isort, pyupgrade, bugbear, and most of pylint. `ruff format` is a >99% Black-compatible drop-in formatter. Both in one Rust binary at 150–200× the speed.

```bash
uv add --dev ruff
uvx ruff check .                # lint
uvx ruff check --fix .          # auto-fix what's safe
uvx ruff check --fix --unsafe-fixes .   # also apply less-safe fixes (review the diff)
uvx ruff format .               # format
```

### Recommended `pyproject.toml` config

```toml
[tool.ruff]
target-version = "py312"
line-length = 100   # 88 (Black default) is fine; 100 is the team-friendly compromise

[tool.ruff.lint]
select = [
    "E", "F", "W",   # pyflakes / pycodestyle
    "I",             # isort
    "UP",            # pyupgrade — auto-modernize syntax
    "B",             # bugbear — common bugs
    "SIM",           # simplifications
    "RUF",           # ruff-native
    "N",             # pep8-naming
    "S",             # bandit security (turn off for tests with per-file-ignores)
    "C4",            # comprehensions
    "PTH",           # use pathlib instead of os.path
    "PIE",           # misc anti-patterns
    "RET",           # return statement hygiene
    "TID",           # tidy imports
    "ARG",           # unused arguments
]
ignore = [
    "E501",          # line length — let formatter handle it
    "S101",          # assert used (fine in tests; restricted by per-file-ignores)
]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101", "ARG"]   # asserts and unused fixture args are fine in tests

[tool.ruff.lint.pydocstyle]
convention = "google"          # if you use docstrings — pick one and stick to it
```

`ruff format` reads `line-length` from the same `[tool.ruff]` block. No separate `[tool.ruff.format]` needed unless you want non-defaults (e.g., `quote-style = "single"`).

### When pylint adds value

Pylint catches semantic issues ruff doesn't yet — deep control-flow analysis, class-inheritance issues, unreachable code via constant folding. Run it as a slow secondary check on safety-critical code; don't make it the primary linter.

## Type checking

### `pyright` — primary default

Pyright is fast, ships in VS Code via Pylance, and has the best correctness-to-speed ratio. Use it for application development.

```bash
uv add --dev pyright
uvx pyright src/
```

Config in `pyproject.toml`:

```toml
[tool.pyright]
include = ["src", "tests"]
pythonVersion = "3.12"
typeCheckingMode = "strict"        # or "standard" if migrating
reportMissingTypeStubs = "warning"
reportUnknownMemberType = "warning"
reportUnknownParameterType = "warning"
```

### `mypy` — library default

Mypy is the lingua franca for distributed libraries. Stubs (`*.pyi` files in `typeshed`) target mypy first. If you ship a library to PyPI, also run mypy in CI — its diagnostics are what most users will see.

```bash
uv add --dev mypy
uvx mypy src/
```

```toml
[tool.mypy]
python_version = "3.12"
strict = true
warn_unreachable = true
warn_unused_ignores = true
files = ["src", "tests"]

[[tool.mypy.overrides]]
module = "some_untyped_dep.*"
ignore_missing_imports = true
```

### `ty` — Astral's checker (watch, don't adopt)

`ty` (formerly red-knot) is dramatically faster than mypy/pyright but still in beta as of late 2025 with ~50% spec conformance. Worth tracking; not yet a primary checker. Try it alongside `pyright` if you want early feedback on Astral's roadmap.

### Pragmatics

- Run **both** pyright (in editor + pre-commit) and mypy (in CI) if you ship a library.
- Type-check `tests/` too — tests are code, and broken fixtures hide there.
- `# type: ignore[arg-type]  # reason: third-party lib has wrong stub` — always specify the error code and a reason comment.
- When a dependency has no types, prefer adding a `*.pyi` stub locally (`stubs/that_lib/__init__.pyi`) and pointing the checker at it rather than ignoring it project-wide.

## `pytest` — testing

Use pytest for everything. `unittest` only when the standard library is a hard constraint.

```bash
uv add --dev pytest pytest-cov pytest-asyncio hypothesis
uv run pytest                   # all tests
uv run pytest -k "auth"         # filter by name
uv run pytest tests/test_foo.py::test_bar -x    # one test, stop on first fail
uv run pytest --lf              # rerun last-failed
uv run pytest -n auto           # parallel (needs pytest-xdist)
```

`pyproject.toml`:

```toml
[tool.pytest.ini_options]
minversion = "8.0"
addopts = "-ra --strict-markers --strict-config"
testpaths = ["tests"]
asyncio_mode = "auto"           # tests just use `async def test_…`; no decorator needed
markers = [
    "slow: marks tests as slow (deselect with -m 'not slow')",
    "integration: requires external services",
]

[tool.coverage.run]
source = ["src"]
branch = true

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "raise NotImplementedError",
    "if TYPE_CHECKING:",
    "if __name__ == .__main__.:",
]
```

### Idiomatic test shape

```python
import pytest


@pytest.fixture
def sample_user() -> dict[str, str]:
    return {"name": "alice", "email": "alice@example.com"}


@pytest.mark.parametrize(
    ("input_", "expected"),
    [
        ("alice", True),
        ("ALICE", True),
        ("", False),
        ("bob bob", False),
    ],
)
def test_valid_username(input_: str, expected: bool) -> None:
    assert is_valid_username(input_) is expected


async def test_async_thing(client) -> None:    # async-mode=auto, no decorator
    response = await client.get("/health")
    assert response.status_code == 200
```

Patterns:

- **Fixtures over `setUp`/`tearDown`.** Scope as narrowly as possible (`function` default).
- **`conftest.py`** for shared fixtures; one per directory, closest to the tests that use it.
- **`@pytest.mark.parametrize`** for table-driven tests — vastly more readable than loops.
- **`hypothesis`** for property-based testing on parsers, serializers, math, anything with an invariant:
  ```python
  from hypothesis import given, strategies as st

  @given(st.text())
  def test_roundtrip(s: str) -> None:
      assert decode(encode(s)) == s
  ```
- **`tmp_path` fixture** for any test that touches the filesystem. Never write to `/tmp` or the repo.
- **Factories** (`factory-boy`, `polyfactory`) when you build many similar objects across tests.

### What not to do

- Don't put logic in `conftest.py` beyond fixtures and hooks.
- Don't use `unittest.mock.patch` without a `with` block or decorator scope — accidental scope leaks are hard to debug.
- Don't share mutable state across tests via module globals; fixtures with scoping exist for this.
- Don't `assert` in production-side code expecting tests to catch the breakage — assertions are stripped by `python -O`.

## Supply chain

- **`uv lock`** writes a hash-pinned lockfile by default. Commit `uv.lock`.
- **`uv lock --upgrade --exclude-newer "1 week ago"`** when refreshing — avoids depending on packages younger than a week, which is your malware-typosquat dodge.
- **`pip-audit`** in CI scans for known CVEs in the lockfile:
  ```bash
  uvx pip-audit --requirement requirements.txt
  uvx pip-audit --strict
  ```
- **`ruff`'s `S` ruleset (bandit)** catches common source-level security smells. `bandit` itself adds little once ruff `S` is on.
- **Don't commit `.env`.** Ship `.env.example`. See [web.md](web.md) for config patterns.

## Pre-commit (optional but common)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.7.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/RobertCraigie/pyright-python
    rev: v1.1.380
    hooks:
      - id: pyright
```

If you want one-tool-runs-everything: `uv tool install pre-commit` and `pre-commit install` once per clone.
