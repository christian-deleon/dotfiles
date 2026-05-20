# Docker Compose

Compose is a declarative shape for "the set of containers I want running together on one host" — services, networks, volumes, secrets, and the wiring between them. Modern Compose is **v2 only** (a Go binary delivered as the `compose` CLI plugin), the file is **`compose.yaml`** (no `version:` field), and the spec is the open Compose Specification at compose-spec.io. The Python `docker-compose` v1 tool is dead — GitHub Actions runners and official Docker images removed it in 2024.

Compose's job: dev environments, CI integration-test harnesses, single-host demos and internal tools. **Not its job:** multi-host production orchestration. Compose has no story for HA, rolling updates, autoscaling, or zero-downtime deploys. When the workload needs any of those, the answer is Kubernetes — defer to the `kubernetes`/`helm`/`flux` skills.

## File shape

```yaml
# compose.yaml — no `version:`, the field is obsolete
name: checkout                       # project name; overrides COMPOSE_PROJECT_NAME

include:
  - path: ./database/compose.yaml    # composable slice — DB owned by another team

services:
  api:
    image: ghcr.io/acme/checkout-api@sha256:...  # digest pin in prod
    build:
      context: ./api
      dockerfile: Dockerfile
      cache_from: [type=registry,ref=ghcr.io/acme/checkout-api:buildcache]
      cache_to:   [type=registry,ref=ghcr.io/acme/checkout-api:buildcache,mode=max]
      platforms:  [linux/amd64, linux/arm64]
      secrets:    [github_token]
    ports:
      - "8080:8080"
    environment:
      LOG_LEVEL: info
      DB_HOST: db
      DB_PASSWORD_FILE: /run/secrets/db_password   # official-image convention
    secrets:
      - db_password
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]
      interval: 10s
      timeout: 2s
      retries: 5
      start_period: 30s
      start_interval: 1s
    deploy:
      resources:
        limits:   { cpus: "1.0", memory: 512M }
        reservations: { cpus: "0.25", memory: 128M }
    develop:
      watch:
        - { action: sync,    path: ./api/src,         target: /app/src }
        - { action: rebuild, path: ./api/go.sum }

  db:
    image: postgres:17@sha256:...
    environment:
      POSTGRES_DB: checkout
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    volumes:
      - db_data:/var/lib/postgresql/data
    secrets: [db_password]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 2s
      retries: 10
      start_period: 5s

  jaeger:
    image: jaegertracing/all-in-one:latest
    profiles: [debug]    # opt-in; only starts with --profile debug

volumes:
  db_data:

secrets:
  db_password:
    file: ./secrets/db_password.txt          # local dev; in prod use external: true
  github_token:
    environment: GITHUB_TOKEN
```

Read top-to-bottom: project name, `include:` for slices owned elsewhere, services with explicit dependencies, profiles for opt-in extras, named volumes for state, secrets as a first-class top-level key. No `version:`, no `links:`, no plaintext passwords in `environment:`.

## What's modern vs obsolete

| Modern | Obsolete |
|---|---|
| `docker compose` (v2, Go plugin) | `docker-compose` (v1, Python) — removed 2024 |
| `compose.yaml` | `docker-compose.yml` (still works; the canonical name has changed) |
| (no `version:` field) | `version: '3.8'` at the top |
| `develop.watch:` block | bind-mounting `./:/app` for dev hot-reload |
| `depends_on.<svc>.condition: service_healthy` + `healthcheck:` | `depends_on: [<svc>]` plain list + `sleep` in entrypoint |
| `secrets:` top-level + per-service | plaintext passwords in `environment:` |
| `include:` for composable slices | hand-maintained `-f base.yml -f ...` chains |
| `deploy.resources.limits` for caps | `mem_limit`/`cpus` legacy shorthands |
| service-name DNS via default network | `links:` |
| `start_interval` in healthchecks | longer `interval` to compensate for slow ready detection |

## `develop.watch` — the modern dev loop

`docker compose watch` (or `docker compose up --watch`) replaces the old bind-mount-the-source-tree-and-pray loop. Each rule under `services.<name>.develop.watch:` declares a watch path, a target inside the container, and one of three actions:

| Action | Effect | Use for |
|---|---|---|
| `sync` | Copy changed files into the running container | Hot-reloading frameworks — FastAPI/Uvicorn `--reload`, Next.js, air for Go, cargo-watch |
| `sync+restart` | Sync, then restart the container | Config files (`nginx.conf`, `redis.conf`) the app reads at startup |
| `rebuild` | Tear down, BuildKit rebuild, restart | Dependency manifest changes (`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`) |

```yaml
develop:
  watch:
    - action: sync
      path: ./api/src
      target: /app/src
      ignore: ["**/*.test.go", "**/__pycache__/**"]
    - action: sync+restart
      path: ./api/config.yaml
      target: /app/config.yaml
    - action: rebuild
      path: ./api/go.sum
    - action: rebuild
      path: ./api/Dockerfile
```

Run `docker compose up --watch` (or `docker compose watch` in a separate terminal). Prefer this over bind mounts wherever the framework supports it — bind mounts carry their own correctness traps (file permissions, inotify watches not propagating across mount boundaries, slow on macOS Docker Desktop).

## Composition — `include`, `extends`, `-f`

Three mechanisms, different jobs:

| Mechanism | Use when |
|---|---|
| **`include:`** (top-level) | You want to compose **reusable application slices** owned by different teams or directories. Each included file is its own Compose application model with its own project dir. Recursive. **The modern default.** |
| **`-f base.yaml -f override.yaml`** (CLI) | Per-environment overlays. `compose.override.yaml` auto-loads alongside `compose.yaml`. Good for small dev/prod deltas. |
| **`extends:`** (service-level) | True service inheritance — service B is service A with three fields tweaked. Niche. Not supported by `docker stack deploy`. |

```yaml
# compose.yaml — top level
include:
  - path: ./infra/db/compose.yaml
  - path: ./infra/cache/compose.yaml
  - path: ./infra/observability/compose.yaml

services:
  api:
    image: ghcr.io/acme/api@sha256:...
```

```yaml
# compose.override.yaml — dev-only, auto-loaded
services:
  api:
    build:
      context: ./api
    environment:
      LOG_LEVEL: debug
    develop:
      watch:
        - { action: sync, path: ./api/src, target: /app/src }
```

`docker compose up` reads both; `docker compose -f compose.yaml -f compose.prod.yaml up` swaps the override.

## `depends_on` with conditions

Plain `depends_on: [db]` only waits for the container to be **started** — the database may still be initialising. That's almost never what you want. The three conditions:

| Condition | Means | Use for |
|---|---|---|
| `service_started` | Container is running | The minimum; weak signal |
| `service_healthy` | Dependency's `healthcheck` is passing | Databases, brokers, anything with a readiness phase — **the right default** |
| `service_completed_successfully` | Dependency exited 0 | Migration jobs, seed scripts, init-container patterns |

```yaml
services:
  api:
    depends_on:
      db:
        condition: service_healthy
        restart: true                # restart api if db restarts (Compose 2.27+)
      migrate:
        condition: service_completed_successfully
```

`restart: true` re-runs the dependent if the dependency restarts — useful for stateful clients that don't reconnect cleanly.

## Healthchecks

Every long-running service gets one. Without a healthcheck, `service_healthy` has nothing to wait on and you're back to `sleep` hacks.

```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]
  interval: 30s         # between checks after start_period
  timeout: 5s           # per check
  retries: 3            # consecutive failures before unhealthy
  start_period: 30s     # grace period after container start
  start_interval: 2s    # check this often inside start_period (2.20.2+)
```

`start_interval` is the key recent addition — it lets a service go healthy seconds after it's actually ready, instead of waiting a full `interval`. Use a small `start_interval` (1-3s) and a longer `interval` (30s+).

`test` forms:
- `["CMD", "binary", "arg"]` — exec form, no shell. Preferred.
- `["CMD-SHELL", "binary arg && other-binary"]` — runs through `/bin/sh -c`. Use when you need shell features (pipes, `&&`).
- `["NONE"]` — explicitly disable an inherited healthcheck.

Distroless images don't have `wget`/`curl`/`sh`. Either copy a static `wget` from a builder stage, ship a tiny in-binary `/healthz` checker, or use `["CMD", "/app", "--healthcheck"]` if your binary supports it.

## Profiles

Opt-in services. `services.<name>.profiles: [debug]` makes a service start only when that profile is activated. Services without `profiles:` always start.

```yaml
services:
  api:
    image: ghcr.io/acme/api@sha256:...
  jaeger:
    image: jaegertracing/all-in-one:latest
    profiles: [debug]
  pgadmin:
    image: dpage/pgadmin4:latest
    profiles: [debug, ops]
```

Activate with `--profile debug` (CLI) or `COMPOSE_PROFILES=debug` (env). Targeting a profiled service directly (`docker compose up jaeger`) starts it regardless of activation, and its dependency chain follows.

Use for: dev-only tooling (Jaeger, pgAdmin, MailHog), expensive test fixtures, debug sidecars, env-specific extras. Keep core application services unassigned.

## Secrets

Plaintext credentials in `environment:` are a smell. Use the top-level `secrets:` block; Compose mounts each as a file at `/run/secrets/<name>` inside the consuming service. The official-image convention is `<VAR>_FILE=/run/secrets/<name>` (Postgres, MariaDB, Redis-Stack, MongoDB all support this).

```yaml
services:
  db:
    image: postgres:17@sha256:...
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt    # local dev only

  api_key:
    environment: API_KEY               # read from env at compose-time

  vault_token:
    external: true                     # engine-managed (Swarm secret, etc.)
```

For real secret stores (Vault, SOPS, 1Password, cloud KMS), populate `.env` from a CLI wrapper before invoking `docker compose`, or use `external: true` against an engine-managed secret. Compose itself has no native integration with external KMS providers — that's deliberate; the spec leaves it to operators.

## Environment & interpolation

```yaml
services:
  api:
    image: ${IMAGE:-ghcr.io/acme/api}:${TAG:?TAG is required}
    environment:
      LOG_LEVEL: ${LOG_LEVEL:-info}
    env_file:
      - path: ./api/.env
        required: true            # default true; false = silently skip if missing
        format: raw               # disable interpolation in the file
```

Interpolation forms:
- `${VAR}` — required, errors if unset
- `${VAR:-default}` — default if unset or empty
- `${VAR-default}` — default if unset (empty value passes through)
- `${VAR:?error message}` — error with message if unset or empty
- `${VAR?error message}` — error if unset

`env_file:` long form (with `path`, `required`, `format`) is the modern shape. Multiple files merge in order, later wins.

## Networks

Compose creates a default bridge network per project (`<project>_default`) and gives every service DNS resolution by service name. **Always reference services by name, never IP** — IPs change on restart.

```yaml
services:
  api:
    networks: [frontend, backend]
  db:
    networks: [backend]
  proxy:
    networks: [frontend]

networks:
  frontend:
  backend:
    internal: true               # no egress; pairs nicely with explicit ingress
```

`network_mode: host` — sharp tool. Kills service DNS (the service is on the host network, can't see the Compose network). Reach for it only when you need host-network access (high-throughput edge proxies, host-network exporters, raw socket access). For most cases, expose the port and use the default bridge.

External networks join an existing engine-managed network across projects:

```yaml
networks:
  shared:
    external: true
    name: platform_shared
```

## Volumes

Three flavours:

```yaml
services:
  db:
    volumes:
      - db_data:/var/lib/postgresql/data       # named
      - ./initdb:/docker-entrypoint-initdb.d:ro # bind
      - type: tmpfs                            # tmpfs (RAM-backed)
        target: /tmp
        tmpfs: { size: 100M }

volumes:
  db_data:                       # default local driver
  shared_models:
    driver: local
    driver_opts:                 # NFS-backed named volume
      type: nfs
      o: addr=fileserver,rw
      device: ":/exports/models"
```

| Flavour | Use for |
|---|---|
| **Named** | State you care about (databases, persistent caches). Engine-managed, survives `docker compose down` (use `-v` to also drop volumes). |
| **Bind** | Mounting config files in read-only, source-tree mounts for dev (but prefer `develop.watch`). |
| **`tmpfs`** | RAM-backed scratch space, runtime secrets that shouldn't hit disk. |
| **Anonymous** (`/data` with no source) | Avoid — orphans after `down`, hard to identify. |

Long-form syntax (`type:`, `source:`, `target:`, `read_only:`, `consistency:`) is preferred for new files; the short `<source>:<target>:<mode>` form still works.

## Resource limits

`deploy.resources` now applies to **standalone Compose**, not just Swarm. The legacy top-level `mem_limit`/`cpus`/`mem_reservation` fields still exist as shorthands but the spec-blessed path is:

```yaml
services:
  api:
    deploy:
      resources:
        limits:
          cpus: "1.5"
          memory: 512M
          pids: 200
        reservations:
          cpus: "0.5"
          memory: 128M
```

Declare both `limits` and `reservations` on every long-running service. Without limits, one runaway container takes the host down.

## Building with Compose

`docker compose build` invokes BuildKit/buildx by default. The `build:` block:

```yaml
services:
  api:
    image: ghcr.io/acme/api:${TAG:-dev}
    build:
      context: ./api
      dockerfile: Dockerfile
      target: runtime              # named stage in a multi-stage Dockerfile
      args:
        VERSION: "1.2.3"
      cache_from:
        - type=registry,ref=ghcr.io/acme/api:buildcache
      cache_to:
        - type=registry,ref=ghcr.io/acme/api:buildcache,mode=max
      platforms: [linux/amd64, linux/arm64]
      secrets: [github_token]
      ssh: [default]
      tags:
        - ghcr.io/acme/api:${TAG:-dev}
        - ghcr.io/acme/api:latest
      labels:
        org.opencontainers.image.source: "https://github.com/acme/api"
```

For anything more complex than a single image, move the build definition to `docker-bake.hcl` and consume it from CI — see [build.md](build.md).

## Production with Compose? Mostly no.

Compose can run a production single-host stack — small internal tools, demos, hobby projects, a CI integration-test harness, a one-off staging box. That's fine. **Where it stops:**

- Multi-host orchestration
- HA / failover
- Rolling updates with health gating
- Autoscaling
- Zero-downtime deploys
- Secrets reconciliation from an external KMS
- Network policies and pod-level isolation

For any of those, the answer is Kubernetes. Defer to the `kubernetes`, `helm`, and `flux` skills — don't try to replicate them with `restart: unless-stopped` and a watchtower sidecar.

The official Compose-in-production guidance is correspondingly modest: pin images by digest, set restart policies, configure log drivers, use `docker compose --no-deps` for surgical updates, and accept the trade-offs. If you find yourself reaching for HAProxy-on-every-host, Consul service discovery, or distributed file storage to make Compose work — stop, switch to Kubernetes.

## Common Compose commands

```bash
docker compose up -d                          # detached
docker compose up --watch                     # dev loop with file sync
docker compose down                           # stop + remove containers/networks
docker compose down -v                        # also drop named volumes (destructive)
docker compose ps                             # services and state
docker compose logs -f api                    # tail logs
docker compose exec api sh                    # exec into a running container
docker compose run --rm api migrate up        # one-shot task with deps
docker compose config                         # render the merged final config
docker compose config --services              # list service names
docker compose pull                           # refresh images
docker compose build --pull                   # rebuild with fresh base layers
docker compose --profile debug up             # activate a profile
docker compose -f compose.yaml -f compose.prod.yaml up    # explicit overlay
```

`docker compose config` is the audit tool — it shows the fully merged, interpolated, validated YAML. Run it before every non-trivial change to confirm what Compose actually sees.

## Anti-patterns roundup

| Smell | Fix |
|---|---|
| `version: '3.8'` at the top | Drop it — obsolete |
| `docker-compose` (hyphenated) in CI scripts | `docker compose` (v2) |
| `links:` between services | Default network DNS resolves by service name |
| `depends_on: [db]` + `sleep 30` in entrypoint | `depends_on.db.condition: service_healthy` + real `healthcheck` |
| Plaintext passwords in `environment:` | `secrets:` block + `<VAR>_FILE=/run/secrets/<name>` |
| Bind-mounting source tree for hot-reload | `develop.watch` with `sync`/`sync+restart`/`rebuild` |
| `latest` tags in production compose files | Digest pin (`image@sha256:…`) |
| `mem_limit: 512m` legacy shorthand | `deploy.resources.limits.memory: 512M` |
| Anonymous volumes for state | Named volumes |
| Hand-maintained chain of `-f` overlays | `include:` for composable slices |
| `restart: always` on a service that crash-loops on bad config | Add a healthcheck; let `service_healthy` upstream propagate the failure |
| Hard-coded `localhost:5432` between services | Service name DNS (`db:5432`) |
| Two services both binding host port 8080 | Different host ports, or front them with a reverse proxy |
| `docker compose up` from a directory called `My_Project` | Project names are lowercase + digits + hyphens; explicitly set `name:` if the dir doesn't conform |
| Compose for a 50-host production fleet | Kubernetes |
