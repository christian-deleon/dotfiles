# Type Hints

Type hints in 2026 are non-optional on public APIs. The language has caught up with what TypeScript and modern Java offer — pattern matching, structural typing, generics with clean syntax, type narrowing — and a type checker (`pyright` or `mypy`) is part of every serious project.

The most common AI failure mode here is writing 2018-era type hints: `Optional[X]`, `Union[X, Y]`, `List[int]`, `Dict[str, int]`, `TypeVar("T")` everywhere, no `Self`, no `Protocol`. All of those are deprecated forms. Use the modern syntax below.

## Modern syntax baseline (3.12+)

| Use | Don't use |
|---|---|
| `X \| None` | `Optional[X]` |
| `X \| Y` | `Union[X, Y]` |
| `list[int]`, `dict[str, int]`, `tuple[int, ...]`, `set[str]` | `typing.List`, `typing.Dict`, etc. |
| `def f[T](xs: list[T]) -> T:` | `T = TypeVar("T")` + `def f(xs: list[T]) -> T:` |
| `type Result[T] = T \| None` | `Result: TypeAlias = T \| None` |
| `def fluent(self) -> Self:` | `T = TypeVar("T", bound="Cls")`, `-> T` |
| `class P(Protocol): def f(self) -> int: ...` | inheritance for "duck-typed interfaces" |
| `Annotated[int, Field(gt=0)]` | bare types where metadata matters |
| `def narrow(x: object) -> TypeIs[int]:` | `TypeGuard[int]` in new 3.13+ code |
| `from collections.abc import Iterable, Mapping, Sequence` | `typing.Iterable`, etc. (deprecated) |

`from __future__ import annotations` at the top of every file (3.10–3.13) is still a good default — defers annotation evaluation, sidesteps circular imports, and lets you forward-reference types without quoting. Unnecessary in 3.14+ but harmless.

## PEP 695 — modern generics (3.12+)

The function-scoped generic syntax is concise and TypeChecker-friendly:

```python
def first[T](xs: list[T]) -> T:
    return xs[0]


class Container[T]:
    def __init__(self, value: T) -> None:
        self._value = value
    def get(self) -> T:
        return self._value


type Result[T] = T | Exception
```

Constraints and bounds:

```python
def widen[T: (int, float)](x: T) -> T: ...    # union constraint
def name[T: Comparable](x: T) -> T: ...        # upper bound
def starred[*Ts](xs: tuple[*Ts]) -> tuple[*Ts]: ...   # variadic
```

The old `TypeVar("T")` syntax still works and is necessary for libraries supporting <3.12. Don't mix the two styles within a file.

## `typing.Self`

For methods that return their own type (fluent APIs, alternative constructors, copy-with-changes):

```python
from typing import Self
from dataclasses import dataclass, replace


@dataclass(frozen=True, slots=True)
class Builder:
    name: str = ""
    count: int = 0

    def with_name(self, name: str) -> Self:
        return replace(self, name=name)

    def with_count(self, count: int) -> Self:
        return replace(self, count=count)
```

`Self` correctly narrows for subclasses — `SubBuilder().with_name("x")` returns `SubBuilder`, not `Builder`.

## `Protocol` — structural typing

Use Protocols for interfaces. No inheritance, no registration, no metaclass dance:

```python
from typing import Protocol


class SupportsClose(Protocol):
    def close(self) -> None: ...


def cleanup(thing: SupportsClose) -> None:
    thing.close()
```

Any class with a `close()` method satisfies `SupportsClose`. This is the right way to type duck-typed APIs in 2026.

`@runtime_checkable` if you need `isinstance(x, MyProtocol)` to work:

```python
from typing import Protocol, runtime_checkable

@runtime_checkable
class Closeable(Protocol):
    def close(self) -> None: ...

isinstance(some_object, Closeable)   # works
```

## `Annotated` — types with metadata

`Annotated[T, ...]` attaches metadata to a type. The metadata is invisible to the type system but visible at runtime — Pydantic, FastAPI, and msgspec all use it:

```python
from typing import Annotated
from pydantic import Field

UserId = Annotated[int, Field(gt=0)]

def get_user(user_id: UserId) -> User: ...
```

FastAPI uses `Annotated` for dependency injection:

```python
from fastapi import Depends

CurrentUser = Annotated[User, Depends(get_current_user)]

@app.get("/me")
def me(user: CurrentUser) -> User:
    return user
```

This is the canonical pattern in modern FastAPI — never `user: User = Depends(get_current_user)` in new code.

## `TypeIs` vs `TypeGuard` (3.13+)

`TypeIs` narrows in *both* branches and is what you want by default. `TypeGuard` only narrows the positive branch — keep using it only when the negative narrowing would be wrong.

```python
from typing import TypeIs


def is_nonzero_int(x: object) -> TypeIs[int]:
    return isinstance(x, int) and x != 0


def f(x: int | str) -> None:
    if is_nonzero_int(x):
        reveal_type(x)   # int
    else:
        reveal_type(x)   # str (because TypeIs narrows both branches)
```

If your library still supports 3.12, `TypeGuard` is the only option there.

## Collections imports

`collections.abc` is the home for `Iterable`, `Mapping`, `Sequence`, `Callable`, `Hashable`, etc. The `typing.Iterable` reexports are deprecated:

```python
from collections.abc import Callable, Iterable, Mapping, Sequence

def process(items: Iterable[str], lookup: Mapping[str, int]) -> Sequence[int]: ...

handler: Callable[[int, int], int] = lambda a, b: a + b
```

`Callable` for callables; `Iterable` when you only need to iterate; `Sequence` when you need indexing and `len`; `Mapping` for read-only dict-like; `MutableMapping` if the caller will write.

## `Literal` and `Final`

```python
from typing import Literal, Final

DEFAULT_PORT: Final = 8080         # type-checker enforces: cannot be reassigned

LogLevel = Literal["debug", "info", "warning", "error"]

def log(level: LogLevel, msg: str) -> None: ...
```

`Literal` is excellent for string/int enums where you don't want to introduce an `Enum` class. Combines well with `match`:

```python
def handle(event: Literal["click", "hover", "submit"]) -> None:
    match event:
        case "click": ...
        case "hover": ...
        case "submit": ...
```

## `NewType` for distinct primitive types

Wrap a primitive to prevent accidental mixing without runtime cost:

```python
from typing import NewType

UserId = NewType("UserId", int)
OrderId = NewType("OrderId", int)

def get_user(uid: UserId) -> User: ...

uid = UserId(123)
oid = OrderId(456)
get_user(oid)   # type error — distinct types
```

At runtime `UserId(x)` is just `x`. Use this freely for IDs, currencies, units.

## `match` for tagged-union dispatch

When you have a sum type (variant-style data), `match` is dramatically clearer than `isinstance` chains:

```python
from dataclasses import dataclass


@dataclass
class TextEvent:
    text: str


@dataclass
class KeyEvent:
    key: str
    modifiers: frozenset[str]


@dataclass
class CloseEvent:
    reason: str


Event = TextEvent | KeyEvent | CloseEvent


def handle(event: Event) -> None:
    match event:
        case TextEvent(text):
            print(f"text: {text}")
        case KeyEvent(key=k, modifiers=m) if "ctrl" in m:
            print(f"chord: ctrl+{k}")
        case KeyEvent(key=k):
            print(f"key: {k}")
        case CloseEvent(reason):
            print(f"closing: {reason}")
```

The type checker verifies exhaustiveness — add a new variant to `Event` and the checker flags unmatched `case` chains.

## Type-checker configuration

### `pyright` (apps — primary)

```toml
[tool.pyright]
include = ["src", "tests"]
pythonVersion = "3.12"
typeCheckingMode = "strict"
reportMissingTypeStubs = "warning"
reportUnknownMemberType = "warning"
reportUnknownVariableType = "warning"
reportUnknownParameterType = "warning"
reportUnknownArgumentType = "warning"
useLibraryCodeForTypes = true
```

`strict` is the right default; loosen specific rules to `"warning"` or `"none"` if a check is too noisy for your codebase.

### `mypy` (libraries)

```toml
[tool.mypy]
python_version = "3.12"
strict = true
warn_unreachable = true
warn_unused_ignores = true
warn_redundant_casts = true
files = ["src", "tests"]

[[tool.mypy.overrides]]
module = ["untyped_lib.*", "another_untyped.*"]
ignore_missing_imports = true
```

`strict = true` enables: `disallow_untyped_defs`, `disallow_untyped_calls`, `disallow_incomplete_defs`, `no_implicit_optional`, `warn_return_any`, plus several others.

## Stubs and PEP 561

If you ship a library:

1. Put an empty `py.typed` marker inside the package: `src/my_lib/py.typed`.
2. Configure the build backend to include it.

If a *dependency* has no types, you have three escalating options:

1. **Local stub file** — `stubs/that_lib/__init__.pyi` next to your code, plus `stubPath = "stubs"` in pyright. Best when you only need a handful of signatures.
2. **`types-…` stub package** from typeshed (if one exists for the library). E.g., `types-requests`.
3. **`ignore_missing_imports = true`** for that module — fastest but type-unsafe.

## Escape hatches

```python
from typing import cast, Any, TYPE_CHECKING

# Tell the checker a value's type without runtime cost
x = cast(int, some_value)

# Anything goes — use sparingly, document why
data: Any = json.loads(text)

# Import only for type checking — sidesteps circular imports and unused-at-runtime deps
if TYPE_CHECKING:
    from .heavy_module import HeavyThing

def process(thing: HeavyThing) -> None: ...
```

When you need `# type: ignore`:

```python
# Bad: silent disable
result = legacy_call(x)  # type: ignore

# Good: specific error code + reason
result = legacy_call(x)  # type: ignore[arg-type]  # reason: third-party stub is wrong
```

`# type: ignore` without an error code disables *all* checks on the line, which masks future regressions. Always specify the code, and document why.

## Reading types in code

`typing.get_type_hints(obj)` resolves string annotations (PEP 563/649) for runtime introspection. **Don't** read `__annotations__` directly in 3.14+ code — it returns lazy proxies:

```python
from typing import get_type_hints

hints = get_type_hints(some_function)  # {"x": int, "return": str}
```

`inspect.signature(obj)` gives you a richer view including parameter kinds and defaults.

## Anti-patterns

- **`Any` as a return type** on a public function — defeats the entire point. Reach for `object`, a `Protocol`, or a union of concrete types.
- **`# type: ignore` without a code** — masks real errors. Use `# type: ignore[error-code]  # reason: ...`.
- **`Union[X, Y]` and `Optional[X]`** in new code — use `X | Y` and `X | None`.
- **`typing.List[int]`, `typing.Dict[str, int]`** — use `list[int]`, `dict[str, int]`.
- **Quoting forward references** in 3.10+ code with `from __future__ import annotations` — unnecessary, just write the type.
- **Re-declaring `T = TypeVar("T")` in every file** — use PEP 695 `def f[T](...)` instead.
- **Mutable types in `Final`** — `FOO: Final[list[str]] = []` doesn't stop `.append`. Use `frozenset`, `tuple`, or `MappingProxyType`.
- **`Optional[X]` with `X = None` default** — the type already says it can be None; the default makes it implicit. Be explicit: `x: X | None = None`.
- **Returning `bool` from a predicate** when `TypeIs` would let the checker narrow — pay the small cost, get the narrowing.
