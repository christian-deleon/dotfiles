# Data Models

Python has five plausible ways to declare a record-shaped object, and most projects end up using three or four of them. The right pick depends on whether the data crosses a trust boundary, how often instances are created, and whether you need validation, conversion, or just typed storage.

The most common AI failure mode here is making everything a Pydantic model. Pydantic validates on every construction, which is the right behavior at I/O boundaries and a tax everywhere else. Internal data carriers stay as `@dataclass`. Only models exposed to user input, external APIs, or config files need Pydantic.

## Decision matrix

| Use case | Pick |
|---|---|
| Internal record, no validation, hashable/comparable | `@dataclass(slots=True, frozen=True)` |
| Internal record, needs converters/validators/inheritance ergonomics | `attrs` (`attrs.define`) |
| External I/O boundary (HTTP body, config file, env vars, JSON message) | **Pydantic v2** (`BaseModel`) |
| High-throughput JSON / MessagePack serialization (10k+/s) | **msgspec** (`msgspec.Struct`) |
| Type the shape of an existing dict (no class, no instance overhead) | `TypedDict` |
| Immutable record where positional iteration matters | `NamedTuple` |
| Tagged union (sum type) | union of `@dataclass` types + `match` |

The headline: **Pydantic at trust boundaries, dataclass inside.** Don't make every internal type a Pydantic model — you pay validation cost on every construction.

## `@dataclass` — the workhorse

For internal records, this is the default. Free `__init__`, `__repr__`, `__eq__`; `frozen=True` for hashability and immutability; `slots=True` for memory + attribute typo protection.

```python
from dataclasses import dataclass, field, replace


@dataclass(slots=True, frozen=True)
class Point:
    x: float
    y: float
    label: str = ""


p1 = Point(1.0, 2.0)
p2 = replace(p1, x=5.0)        # immutable update — return a new instance
hash(p1)                        # works because frozen
```

`slots=True`:
- Memory: ~40% less per instance.
- Attribute safety: assigning `p.z = 3.0` raises (would silently succeed without slots).
- Trade-off: no `__dict__`, can't mix with multiple inheritance casually.

`frozen=True`:
- Cannot assign to fields after construction (`p.x = 5` raises).
- Becomes hashable.
- Pair with `replace()` for "update" operations.

Use `field(default_factory=list)` for mutable defaults — never `= []`:

```python
@dataclass(slots=True)
class Cart:
    items: list[str] = field(default_factory=list)
```

### When dataclass is wrong

- Validating user input → Pydantic.
- Cross-field constraints → attrs validators, or Pydantic `@model_validator`.
- Converting input on construction (string → datetime) → attrs converters, or Pydantic.
- Inheritance with overridden fields → dataclass works but the rules get awkward; attrs is cleaner.

## `attrs` — when dataclass isn't enough

`attrs` (`pip install attrs`) is the older, more featureful sibling of dataclass. Use it when you need converters, validators, or richer inheritance:

```python
import attrs
from datetime import datetime


def _to_datetime(v: str | datetime) -> datetime:
    return v if isinstance(v, datetime) else datetime.fromisoformat(v)


@attrs.define
class Event:
    name: str = attrs.field(validator=attrs.validators.instance_of(str))
    occurred: datetime = attrs.field(converter=_to_datetime)
    tags: frozenset[str] = attrs.field(factory=frozenset, converter=frozenset)


Event(name="login", occurred="2026-05-19T12:00:00", tags=["auth"])
# Event(name='login', occurred=datetime(...), tags=frozenset({'auth'}))
```

`@attrs.define` is roughly `@dataclass(slots=True)` with converters, validators, and a more thoughtful inheritance model. `@attrs.frozen` is `frozen=True`. Use `@attrs.define(eq=False)` if you want identity equality.

Converters run on every assignment (with `on_setattr=attrs.setters.convert`); they're a clean way to normalize input without writing `__post_init__`.

## Pydantic v2 — the I/O boundary

Pydantic v2 (Rust-backed `pydantic-core`) is the standard for parsing/validating external data: HTTP bodies, config files, env vars, queue messages, anything untrusted.

```python
from pydantic import BaseModel, EmailStr, Field, field_validator


class CreateUser(BaseModel):
    model_config = {"frozen": True, "str_strip_whitespace": True}

    name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    age: int = Field(ge=13, le=130)
    tags: list[str] = Field(default_factory=list)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, v: str) -> str:
        return v.title()


# Parsing
user = CreateUser.model_validate({"name": "  alice ", "email": "a@b.c", "age": 30})
user.name           # "Alice"

# Serialization
user.model_dump()        # dict
user.model_dump_json()   # bytes
```

Patterns:

- **`model_validate(data)`** for parsing dicts; **`model_validate_json(bytes_or_str)`** for parsing JSON directly (faster, single-pass).
- **`model_dump()`** for dict output; **`model_dump_json()`** for JSON.
- **`model_config = {...}`** for class-level settings — replaces the v1 `class Config:` pattern.
- **`Field(...)`** for validation constraints (`min_length`, `ge`, `le`, `pattern`, etc.) and metadata.
- **`field_validator`** for per-field logic; **`model_validator`** for cross-field constraints.
- **`Annotated[T, Field(...)]`** is preferred over `field_name: T = Field(...)` for reuse:

  ```python
  from typing import Annotated

  PositiveInt = Annotated[int, Field(gt=0)]

  class Order(BaseModel):
      user_id: PositiveInt
      total_cents: PositiveInt
  ```

### Pydantic vs dataclass — when to switch

The boundary is sharp: **does this data come from outside the program?** If yes, Pydantic. If no, dataclass. Don't blur the line — half the performance complaints about "Pydantic is slow" come from using it for internal objects that get re-validated on every construction.

A clean architecture:

```
HTTP layer → Pydantic models (validate, then convert to internal)
                 ↓
Internal layer → dataclass / attrs (no re-validation)
                 ↓
DB layer → SQLAlchemy or msgspec
```

### `pydantic-settings` for config

`pydantic-settings` is the canonical way to load configuration from env vars + `.env` + secret stores:

```python
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="MYAPP_",
        env_nested_delimiter="__",
    )

    database_url: str
    log_level: str = "INFO"
    debug: bool = False
    api_key: str = Field(..., min_length=20)


settings = Settings()    # reads env vars, then .env, then defaults; raises if invalid
```

Twelve-factor philosophy: env vars first, `.env` for local dev only, never commit secrets. See [web.md](web.md) for the full pattern.

## msgspec — high-throughput serialization

`msgspec` (`pip install msgspec`) is ~2–5× faster than Pydantic v2, with a `Struct` type that doubles as a dataclass. Use it when serialization is in the hot path — message queues, high-fanout RPC, log shipping, event streaming.

```python
import msgspec


class Event(msgspec.Struct, frozen=True):
    id: str
    timestamp: float
    payload: dict[str, str]


# Parsing
raw = b'{"id": "abc", "timestamp": 1234.5, "payload": {"k": "v"}}'
event = msgspec.json.decode(raw, type=Event)

# Serialization
msgspec.json.encode(event)   # bytes
msgspec.msgpack.encode(event)   # bytes (MessagePack)
```

Trade-offs vs Pydantic:

- **Faster, leaner.** `Struct` has slots, low memory, fast encode/decode.
- **Less ergonomic.** No `Annotated[T, Field(...)]` ergonomics, fewer built-in validators, smaller community.
- **Strict typing.** Less coercion than Pydantic — you'll see type errors where Pydantic would silently coerce.

Reach for msgspec when you've profiled and Pydantic is the bottleneck, or when you're building infrastructure that handles millions of small objects.

## `TypedDict` — typed dict shapes

When you can't avoid dicts (legacy APIs, JSON responses you don't want to wrap), `TypedDict` types the shape without introducing a class:

```python
from typing import TypedDict


class UserDict(TypedDict):
    id: int
    name: str
    email: str


def show(user: UserDict) -> None:
    print(user["name"])
```

`TypedDict` is *just typing* — at runtime it's a plain dict. There's no validation, no constructor overhead, no `isinstance` check. Use it to type an existing dict-shaped piece of data; don't reach for it when you control the data.

`NotRequired` for optional keys (3.11+):

```python
from typing import TypedDict, NotRequired


class Config(TypedDict):
    host: str
    port: int
    tls: NotRequired[bool]   # may or may not be present
```

## `NamedTuple` — niche

`NamedTuple` is fine for small immutable records where positional iteration matters (returning multiple values from a function, coordinates, color tuples). It's a `tuple` at runtime, so it supports indexing and unpacking:

```python
from typing import NamedTuple


class Range(NamedTuple):
    start: int
    end: int


r = Range(0, 10)
start, end = r        # tuple unpacking
r[0]                  # indexing
```

In practice, `@dataclass(frozen=True, slots=True)` is more flexible and almost always the better default — reach for `NamedTuple` only when you specifically need tuple semantics.

## Tagged unions / sum types

Python doesn't have `enum class` like Rust, but a union of dataclasses + `match` covers the same ground:

```python
from dataclasses import dataclass


@dataclass(slots=True, frozen=True)
class Connected:
    session_id: str


@dataclass(slots=True, frozen=True)
class Disconnected:
    reason: str


@dataclass(slots=True, frozen=True)
class Connecting:
    attempt: int


State = Connected | Disconnected | Connecting


def render(state: State) -> str:
    match state:
        case Connected(session_id):
            return f"online ({session_id})"
        case Connecting(attempt):
            return f"connecting (attempt {attempt})"
        case Disconnected(reason):
            return f"offline: {reason}"
```

The type checker enforces exhaustiveness. Add a new variant to `State` and unmatched `case` chains get flagged.

For Pydantic discriminated unions (different shapes by a tag field), use the `discriminator` setting:

```python
from typing import Annotated, Literal
from pydantic import BaseModel, Field


class TextMessage(BaseModel):
    kind: Literal["text"]
    body: str


class ImageMessage(BaseModel):
    kind: Literal["image"]
    url: str


Message = Annotated[TextMessage | ImageMessage, Field(discriminator="kind")]
```

Pydantic uses the `kind` field to pick the right model at parse time.

## Hashing, comparison, ordering

- `@dataclass` gives `__eq__` by default. `frozen=True` gives `__hash__`. `order=True` gives `__lt__/__gt__/etc.`
- `@dataclass(eq=False)` for identity equality (rare).
- For ordering, prefer `functools.total_ordering` or write the comparisons explicitly.
- Equality always respects type by default; `Point(1, 2) != Point3D(1, 2, 0)` even if the fields overlap.

## Common mistakes

- **Mutable default field**: `tags: list[str] = []` — must be `field(default_factory=list)`.
- **Pydantic everywhere internally** — every construction pays validation cost. Use dataclass for internal data, Pydantic at the boundary.
- **`@dataclass` without `slots=True`** in new 3.10+ code — slots is essentially free memory savings.
- **Mixing `dict` and `TypedDict`** — once you've typed it, treat it like a dict; don't add methods, that's a class's job.
- **Using `NamedTuple` everywhere out of habit** — `@dataclass(frozen=True, slots=True)` is more flexible.
- **Calling `Pydantic.model_dump()` then `json.dumps()`** — use `model_dump_json()` directly, it's faster.
- **Validating on every `__init__`** for performance-sensitive paths — at the I/O boundary, validate once; inside the program, trust the type.
