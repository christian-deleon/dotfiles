# Web Services & HTTP

Python's web stack in 2026 is two-tier: **FastAPI** for new APIs, **Django** when you need the full-stack story (ORM, migrations, admin, auth, templates) bundled. Everything else is a special case. `requests` is legacy; new client code uses `httpx`.

The most common AI failure mode here is reaching for old patterns: `requests` in async code (blocking, ruins the event loop), `Flask` for new APIs (no async, no validation, smaller ecosystem in 2026), `os.environ["KEY"]` scattered through the codebase instead of a validated settings object, and `print()` for logging in services.

## Decision matrix — pick a framework

| Need | Pick | Notes |
|---|---|---|
| JSON API, async-first | **FastAPI** | Default for new APIs; OpenAPI schema for free; Pydantic validation |
| Low-level ASGI primitives, no framework opinions | **Starlette** | FastAPI is built on this; reach down when FastAPI is too opinionated |
| Full-stack web app with ORM, admin, auth, templates | **Django** | 5.x has solid async; the right pick when you'd otherwise glue half-a-dozen libs |
| Tiny app, no async needs, legacy codebase | Flask | Only when the team already knows it well; not a 2026 default |
| Real-time (WebSockets, SSE, long-lived connections) | FastAPI or Starlette | Either; FastAPI has nicer ergonomics |
| GraphQL | Strawberry | Built on FastAPI/Starlette; type-hint-driven schema |
| Background jobs | Arq, Dramatiq, or Celery | Arq for async/Redis-only; Dramatiq for sync; Celery for the most features (and complexity) |

## HTTP clients — `httpx` only

`httpx` is the modern, sync+async, HTTP/2-capable client. Replaces `requests` for new code:

```python
import httpx

# Sync — same shape as requests
r = httpx.get("https://example.com", timeout=10.0)
r.raise_for_status()
data = r.json()

# Sync with a session (connection pooling, default headers)
with httpx.Client(base_url="https://api.example.com", timeout=10.0) as client:
    r = client.get("/users", params={"limit": 10})
    r.raise_for_status()

# Async
async with httpx.AsyncClient(base_url="https://api.example.com") as client:
    r = await client.get("/users")
    r.raise_for_status()
```

Rules:

- **Always set a timeout.** The default is no timeout; in production this hangs forever. Pick a real value (`timeout=httpx.Timeout(10.0, connect=2.0)`).
- **Use `Client`/`AsyncClient` as a context manager** — it pools connections; without it, every request opens a new TCP connection.
- **Call `r.raise_for_status()`** unless you're explicitly handling non-2xx codes. Silent 5xx is the worst kind of bug.
- **Pass `params={...}` for query strings**, not `f"?{...}"`. Encoding is automatic.
- **Pass `json=...` for JSON bodies**, not `data=json.dumps(...)`.
- **For retries**, use `httpx-retries` or wrap with `tenacity`. `httpx` itself does not retry by default.

## FastAPI — the default for new APIs

FastAPI is the default. It's an ASGI framework built on Starlette + Pydantic, with type-hint-driven request validation, dependency injection, and OpenAPI/Swagger out of the box.

### Minimum viable app

```python
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel


app = FastAPI(title="my-app", version="0.1.0")


class CreateUser(BaseModel):
    name: str
    email: str


class User(BaseModel):
    id: int
    name: str
    email: str


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/users", status_code=201)
async def create_user(body: CreateUser) -> User:
    return User(id=1, name=body.name, email=body.email)


@app.get("/users/{user_id}")
async def get_user(user_id: int) -> User:
    if user_id < 1:
        raise HTTPException(status_code=404, detail="not found")
    return User(id=user_id, name="alice", email="a@b.c")
```

Run with:

```bash
uvx fastapi dev app.py        # dev server (uvicorn under the hood, with reload)
uvx fastapi run app.py        # prod server
# or directly:
uvx uvicorn app:app --host 0.0.0.0 --port 8000
```

### Project layout for a real service

```
my-service/
├── pyproject.toml
├── src/my_service/
│   ├── __init__.py
│   ├── main.py             # FastAPI() instance + middleware + lifespan
│   ├── config.py           # pydantic-settings
│   ├── logging.py          # dictConfig setup
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── users.py        # APIRouter for /users
│   │   └── orders.py
│   ├── models/             # Pydantic request/response models
│   ├── services/           # business logic, not framework-aware
│   ├── db/                 # repository layer
│   └── dependencies.py     # shared Depends()
└── tests/
```

Routers keep `main.py` small:

```python
# src/my_service/routers/users.py
from fastapi import APIRouter, Depends

router = APIRouter(prefix="/users", tags=["users"])


@router.get("")
async def list_users() -> list[User]: ...


@router.get("/{user_id}")
async def get_user(user_id: int) -> User: ...


# src/my_service/main.py
from fastapi import FastAPI
from .routers import users, orders

app = FastAPI()
app.include_router(users.router)
app.include_router(orders.router)
```

### Dependency injection — use `Annotated`

The modern FastAPI pattern. Define typed dependencies once, reuse them:

```python
from typing import Annotated
from fastapi import Depends

from .config import Settings, get_settings


SettingsDep = Annotated[Settings, Depends(get_settings)]


def get_db(settings: SettingsDep) -> Database:
    return Database(settings.database_url)


DbDep = Annotated[Database, Depends(get_db)]


@app.get("/users/{user_id}")
async def get_user(user_id: int, db: DbDep) -> User:
    return await db.fetch_user(user_id)
```

Never write `db: Database = Depends(get_db)` in new code — `Annotated` is the canonical form and composes better with type checkers and editors.

### Lifespan, startup, shutdown

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI


@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    app.state.db = await Database.connect(settings.database_url)
    try:
        yield
    finally:
        # shutdown
        await app.state.db.close()


app = FastAPI(lifespan=lifespan)
```

The old `@app.on_event("startup")` decorators are deprecated. Use `lifespan`.

### Error handling

Custom exception → consistent HTTP response:

```python
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


class AppError(Exception):
    def __init__(self, status: int, message: str) -> None:
        self.status = status
        self.message = message


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(status_code=exc.status, content={"error": exc.message})
```

Then your routes raise `AppError(404, "not found")` and the handler formats it.

### Background tasks

For lightweight "fire-and-forget after response" work (logging, cleanup), `BackgroundTasks`:

```python
from fastapi import BackgroundTasks


@app.post("/notify")
async def notify(body: NotifyBody, bg: BackgroundTasks) -> dict[str, str]:
    bg.add_task(send_email, body.address)
    return {"queued": "ok"}
```

For serious background work (retries, scheduling, durability), use Arq/Dramatiq/Celery — not BackgroundTasks.

## Django — when you need the full stack

Use Django when you'd otherwise reach for ORM + migrations + admin + auth + templates + sessions and glue them together. Django 5.x has solid async support; you can mix `async def` views with sync ORM calls (which run in a thread pool transparently).

```python
# views.py
from django.http import JsonResponse
from .models import User


async def list_users(request):
    users = [u async for u in User.objects.all()]
    return JsonResponse({"users": [{"id": u.id, "name": u.name} for u in users]})
```

For pure-API Django services, **Django REST Framework** (DRF) is the standard. But for new API-only services, FastAPI is usually a better fit — DRF carries Django's full weight.

## Starlette — bare ASGI

Reach for Starlette when FastAPI's opinions get in your way (custom routing, no Pydantic, you're building middleware or a framework). It's the foundation FastAPI sits on, and stays close to the ASGI spec.

```python
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route


async def homepage(request):
    return JSONResponse({"hello": "world"})


app = Starlette(routes=[Route("/", homepage)])
```

If you're not sure whether you want Starlette or FastAPI, you want FastAPI.

## ASGI servers

| Server | Use when |
|---|---|
| **uvicorn** | The default. Cython-accelerated, mature, what FastAPI ships with. |
| **hypercorn** | HTTP/2 or HTTP/3 needed (uvicorn is HTTP/1.1 only). |
| **granian** | Rust-based; raw throughput matters; you've benchmarked and uvicorn is the bottleneck. |
| **daphne** | Django Channels (WebSockets in Django). |

WSGI (`gunicorn`, `mod_wsgi`) is legacy for new services — async support is bolted on. Use ASGI for new work.

In production behind a proxy:

```bash
uvicorn my_service.main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --workers 4 \
    --proxy-headers \
    --forwarded-allow-ips '*'
```

`--workers N` runs N processes; pair with a reverse proxy (nginx, Caddy) or a load balancer.

## Config — `pydantic-settings`

Twelve-factor: configuration comes from the environment. Validate at startup, fail fast on missing/invalid config.

```python
# src/my_service/config.py
from functools import lru_cache

from pydantic import Field, PostgresDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="MYSVC_",
        env_nested_delimiter="__",
        case_sensitive=False,
        extra="forbid",
    )

    env: str = Field(default="dev", pattern="^(dev|staging|prod)$")
    log_level: str = Field(default="INFO")
    database_url: PostgresDsn
    redis_url: str
    api_key: str = Field(min_length=20)
    cors_origins: list[str] = Field(default_factory=list)


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

Rules:

- **Validate at startup**, not at first use. Call `get_settings()` in your lifespan to fail fast.
- **Never `os.environ["MYSVC_DATABASE_URL"]`** scattered through the code. Inject `Settings` instead.
- **`extra="forbid"`** so typos in env var names raise instead of silently being ignored.
- **`.env` for local dev only.** Production secrets come from the orchestrator (K8s secrets, AWS Secrets Manager, Vault) injected as env vars.
- **Never commit `.env`.** Ship `.env.example`.

## Logging

### Library code

```python
import logging

logger = logging.getLogger(__name__)


def do_work() -> None:
    logger.info("starting work")
    try:
        ...
    except Exception:
        logger.exception("work failed")    # logs the traceback too
        raise
```

Always `getLogger(__name__)`. Never `print()`. Never configure the root logger from a library.

### App code — configure once, at startup

```python
# src/my_service/logging.py
import logging.config
from .config import get_settings


def configure_logging() -> None:
    settings = get_settings()
    logging.config.dictConfig({
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "json": {
                "()": "pythonjsonlogger.json.JsonFormatter",
                "fmt": "%(asctime)s %(levelname)s %(name)s %(message)s",
            },
            "console": {
                "format": "%(asctime)s %(levelname)-8s %(name)s: %(message)s",
            },
        },
        "handlers": {
            "default": {
                "class": "logging.StreamHandler",
                "formatter": "json" if settings.env == "prod" else "console",
                "stream": "ext://sys.stderr",
            },
        },
        "root": {
            "level": settings.log_level,
            "handlers": ["default"],
        },
        "loggers": {
            "uvicorn.access": {"level": "WARNING"},
        },
    })
```

Call `configure_logging()` once in `lifespan` startup.

### `structlog` for services

`structlog` is the 2025–2026 preferred structured logger. It composes processors, integrates cleanly with OpenTelemetry trace/span IDs, and produces JSON or human-readable output from the same configuration:

```python
import structlog


structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer(),
    ],
    cache_logger_on_first_use=True,
)


logger = structlog.get_logger()
logger.info("user_login", user_id=42, ip="10.0.0.1")
# {"timestamp": "...", "level": "info", "event": "user_login", "user_id": 42, "ip": "10.0.0.1"}
```

Bind context for a request, retrieve everywhere downstream:

```python
structlog.contextvars.bind_contextvars(request_id=req.headers["x-request-id"])
# ... any logger.info() in this request will include request_id
```

`loguru` is the alternative if developer experience matters more than ecosystem integration; harder to wire to OpenTelemetry.

## OpenTelemetry

OTel is mainstream for services in 2026. The Python auto-instrumentation packages cover FastAPI, Django, httpx, asyncpg, psycopg, redis, kafka, and most other libraries you'll use:

```bash
uv add opentelemetry-distro opentelemetry-exporter-otlp
uvx opentelemetry-bootstrap -a install   # installs instrumentation packages
```

Then run with auto-instrumentation:

```bash
opentelemetry-instrument \
    --service_name my-service \
    --exporter_otlp_endpoint http://collector:4317 \
    uvicorn my_service.main:app
```

Or instrument manually inside the app:

```python
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

FastAPIInstrumentor.instrument_app(app)
tracer = trace.get_tracer(__name__)


with tracer.start_as_current_span("custom_work"):
    ...
```

Trace and span IDs flow into `structlog` via the contextvars merge — no manual plumbing once both are configured.

## Database access

Pick by stack:

| Style | Pick | Notes |
|---|---|---|
| Async PostgreSQL, raw SQL preferred | **asyncpg** | Fastest; no ORM ceremony |
| Async + ORM | **SQLAlchemy 2.x** (`async_engine`) | The default async ORM in 2026; v2 syntax is clean |
| Django app | **Django ORM** | Don't fight the framework |
| Microservice with a few tables | **SQLAlchemy Core** (not ORM) or **asyncpg + msgspec** | Lower ceremony than the ORM |
| MongoDB | **motor** (async) or **pymongo** | Pydantic models for serialization |
| Redis | **redis-py** (async) | The asyncio API is well-supported |

SQLAlchemy 2.x async, minimum viable shape:

```python
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_session():
    async with SessionLocal() as session:
        yield session


SessionDep = Annotated[AsyncSession, Depends(get_session)]
```

## Testing services

Use `pytest` + `httpx.AsyncClient` against the ASGI app — no need to spin up a real server:

```python
import pytest
from httpx import AsyncClient, ASGITransport
from my_service.main import app


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
```

For tests that need real DB/Redis, run them in Docker via `testcontainers-python` or fixtures that talk to a per-test schema/database.

## Common service mistakes

- **`requests` in async routes.** Blocks the event loop. Always `httpx.AsyncClient`.
- **No `.raise_for_status()` on HTTP calls.** 5xx errors get silently treated as success.
- **No timeouts on `httpx`/`asyncio`.** Default is "forever"; production hangs.
- **`os.environ[...]` scattered.** Centralize in `Settings`; validate at startup.
- **`print()` in services.** Use `logging` or `structlog`.
- **Configuring logging in a library.** Libraries `getLogger(__name__)`; apps configure.
- **Blocking the event loop with CPU work.** Offload to `asyncio.to_thread` or a process pool.
- **`@app.on_event("startup")`** — deprecated; use `lifespan`.
- **`Depends(get_x)` instead of `Annotated[X, Depends(get_x)]`.** Modern FastAPI is `Annotated`-first.
- **Returning a Pydantic model from a sync function that mutates it.** Pydantic v2 models are validated on assignment; this can be surprising.
- **No graceful shutdown.** Use `lifespan` to close DB pools, drain queues, close HTTP clients.
