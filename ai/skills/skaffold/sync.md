# Skaffold File Sync & Lifecycle Hooks

`sync:` copies changed files into a running container without rebuilding the image. `hooks:` runs commands at lifecycle points (`before`/`after` for `build`/`sync`/`deploy`/`render`/`test`). Together they cover the "I changed something, propagate it fast" problem.

The mental model: **`sync:` is for files**, **`hooks:` is for actions**. If the change is "copy this file into the container," it's sync. If the change is "run a script when the file lands," it's a sync hook. If the change requires the image to actually be different (compiled binary, native deps), it's a rebuild — don't try to sync your way out of it.

## The three sync modes

| Mode | Schema | When |
|---|---|---|
| **`sync.manual:`** | Explicit `src`/`dest`/`strip` triples | Always your first choice. Boring, reliable, debuggable. |
| **`sync.infer:`** | List of glob patterns; Skaffold reads `COPY` in Dockerfile to derive `dest` | Single-stage Dockerfiles only. Fragile on anything non-trivial. |
| **`sync.auto: true`** | Builder declares what's syncable | Only `buildpacks` and `jib`. If you're using one, prefer this over manual. |

### `manual:` — the workhorse

```yaml
artifacts:
  - image: ghcr.io/myorg/api
    docker:
      dockerfile: Dockerfile
    sync:
      manual:
        - src: "templates/**/*.html"
          dest: /app/templates                         # absolute path inside the container
        - src: "static/**/*"
          dest: /app/static
        - src: "src/**/*.py"
          dest: /app/src
          strip: src/                                  # strip leading path before mapping
        - src: "config/*.yaml"
          dest: /app/config
```

`strip:` is the field people forget. Without it, `src: "src/foo/bar.py"` lands at `<dest>/src/foo/bar.py`. With `strip: src/`, it lands at `<dest>/foo/bar.py` — matching what `COPY src/ /app/src/` produces at build time.

Glob semantics:
- `*` matches one path segment.
- `**` matches any number of segments.
- `?` matches a single character.
- Patterns are evaluated relative to the artifact's `context:`.

### `infer:` — when it's safe

```yaml
sync:
  infer:
    - "templates/**"
    - "static/**"
```

Skaffold finds the `COPY templates/ /app/templates/` line in the Dockerfile and infers `dest: /app/templates`. Requirements:

- **Single-stage Dockerfile**, or all referenced `COPY`s in the final stage.
- The matched path appears in **exactly one** `COPY` instruction (otherwise Skaffold can't decide where it goes).
- Glob in the sync pattern is a subset of what the `COPY` already takes.

Fails silently in subtle ways. If you have to debug sync more than once, switch to `manual:`.

### `auto: true` — buildpacks and jib

```yaml
artifacts:
  - image: ghcr.io/myorg/web
    buildpacks:
      builder: paketobuildpacks/builder-jammy-base
    sync:
      auto: true
```

The builder ships sync metadata (which paths can be synced, where they map). Skaffold reads it. Zero config from you. This is why `buildpacks` is a strong inner-loop choice for Node/Python/Ruby/Go monorepos.

For `jib`, `sync: auto` syncs class files into the running JVM (matching Jib's layering); restart-on-sync handled by JVM hot-swap.

## Hot-reload — sync alone isn't enough

`sync:` puts files into the container. **The process inside the container then has to notice.** Three paths:

1. **The process watches its own files** (Flask debug, FastAPI `--reload`, nodemon, Vite HMR, `air` for Go, Django `runserver`, Spring Devtools, Rails). This is the cleanest path. The container's entrypoint runs the framework in dev mode; sync drops in new files; the framework reloads.
2. **Skaffold restarts the process** via sync hooks (next section). Used when the runtime has no file-watcher but is cheap to restart.
3. **You give up and rebuild.** For compiled languages with no live-reload story (small Go binaries, native CLIs), rebuilding is often as fast as a restart anyway — the image is tiny, the layer cache is hot.

### Per-framework recipes

| Stack | Inner-loop entrypoint | Sync target |
|---|---|---|
| Go | `air` (https://github.com/air-verse/air) with `air.toml` watching `.go` files | Sync only assets/templates; let `air` watch+rebuild source |
| Python (Flask) | `flask --app app run --debug` | Sync `**/*.py` — Flask's reloader picks it up |
| Python (FastAPI) | `uvicorn app:app --reload` | Sync `**/*.py` — uvicorn watches and reloads |
| Python (Django) | `python manage.py runserver` | Sync `**/*.py` + templates |
| Node (general) | `nodemon --ext js,ts ...` | Sync `**/*.{js,ts}` |
| Node (Next.js dev) | `next dev` | Sync `app/**`, `pages/**`, `public/**` |
| Node (Vite) | `vite` | Sync `src/**` — HMR over Vite's WebSocket |
| Java (Spring) | `mvn spring-boot:run` with Devtools on classpath | Use `jib` + `sync.auto: true` |
| Ruby (Rails) | `bin/rails server` | Sync `app/**`, `config/**` — Rails reloader |
| Rust | No good live-reload story | Rebuild; cache the `target/` dir between builds |

The container entrypoint runs the dev-mode reloader. Build it into a `dev` target in the Dockerfile or a debug profile that swaps the command:

```yaml
profiles:
  - name: dev
    patches:
      - op: replace
        path: /manifests/helm/releases/0/setValueTemplates/command
        value: ["uvicorn", "app:app", "--reload", "--host", "0.0.0.0"]
```

## Lifecycle hooks

Hooks let you run commands at specific lifecycle points. Two runner types: `host:` (runs on your laptop) and `container:` (runs inside a pod).

```yaml
build:
  artifacts:
    - image: ghcr.io/myorg/svc
      hooks:
        before:
          - command: ["go", "generate", "./..."]
            os: [darwin, linux]
        after:
          - command: ["./scripts/notify-build.sh", "{{.IMAGE_FULLY_QUALIFIED}}"]

  # Per-artifact sync hooks
      sync:
        manual:
          - src: "templates/**"
            dest: /app/templates
        hooks:
          before:
            - host:
                command: ["echo", "syncing templates"]
          after:
            - container:
                command: ["pkill", "-HUP", "nginx"]   # SIGHUP the process inside the pod

# Deploy-level hooks (run at deploy lifecycle)
deploy:
  kubectl: {}
  hooks:
    before:
      - host:
          command: ["./scripts/db-migrate.sh"]
    after:
      - host:
          command: ["./scripts/smoke-test.sh", "http://localhost:8080"]
```

### Hook anatomy

| Field | Notes |
|---|---|
| `host.command` | Shell-style arg list. Runs in the directory of `skaffold.yaml`. Inherits Skaffold's env. |
| `host.os` | Restrict by OS: `[darwin, linux, windows]`. Skip silently on others. |
| `host.dir` | Override the working directory. |
| `container.command` | Runs `kubectl exec` against the synced container. |
| `container.containerName` / `container.podName` | Target specific containers when the pod has multiple. Glob-matched. |

Hook timing:

| Hook block | Fires |
|---|---|
| `build.artifacts[].hooks.before` | Before that artifact builds |
| `build.artifacts[].hooks.after` | After that artifact builds successfully |
| `build.artifacts[].sync.hooks.before` | Before files are copied into the container |
| `build.artifacts[].sync.hooks.after` | After files are copied — **the restart hook** |
| `deploy.hooks.before` | Before deploying (apply/install) |
| `deploy.hooks.after` | After deployment is healthy |
| `manifests.hooks.before` / `after` | Around manifest rendering (v2) |
| `test.hooks.before` / `after` | Around the test phase |

### Real hook patterns

**Codegen before build** — generate clients, gRPC bindings, GraphQL types:

```yaml
build:
  artifacts:
    - image: ghcr.io/myorg/api
      hooks:
        before:
          - command: ["buf", "generate"]
          - command: ["go", "generate", "./..."]
```

**Restart on sync** — when the process doesn't watch its own files:

```yaml
sync:
  manual:
    - src: "config/**"
      dest: /etc/myapp
  hooks:
    after:
      - container:
          command: ["kill", "-HUP", "1"]               # PID 1 reloads on SIGHUP
```

**DB migration after deploy** — wait for the cluster to be healthy, then migrate:

```yaml
deploy:
  kubectl: {}
  hooks:
    after:
      - host:
          command: ["./scripts/migrate.sh"]
          os: [darwin, linux]
```

**Per-OS dev-data seed** — only on Mac, only after deploy:

```yaml
deploy:
  kubectl: {}
  hooks:
    after:
      - host:
          os: [darwin]
          command: ["./scripts/seed-dev-data-mac.sh"]
```

## Sync gotchas

| Symptom | Likely cause |
|---|---|
| "File synced" log but the change doesn't appear | Process isn't watching files — add a restart hook or run the framework's dev-mode reloader |
| Files land at the wrong path | Missing `strip:` — `src/foo.py` lands at `<dest>/src/foo.py` without it |
| Permission denied after sync | Container user doesn't own the dest dir; rebuild with correct `chown` in Dockerfile, or run as root in dev |
| Sync triggers a full rebuild instead | The changed file matches an `artifacts[].dependencies.paths` pattern *and* a sync rule — sync wins only if the sync rule matches first; tighten `dependencies.paths` |
| `infer:` syncs work locally but not in CI | CI's Dockerfile is multi-stage; infer can't follow. Switch to `manual:` |
| `buildpacks` + `auto: true` doesn't sync at all | Builder image doesn't ship sync metadata — paketo `*-base` does, custom builders may not |
| Sync hook `container:` runs but exits 1 | Container doesn't have the binary you're calling (e.g. `pkill` not in distroless); use `kill -HUP 1` or bake the tool in |

## When to sync vs when to rebuild

| Change is to… | Action |
|---|---|
| Interpreted source (Python, Node, Ruby) | Sync + framework reloader |
| Templates, configs, static assets | Sync (no restart usually needed for templates if the framework reloads them) |
| Compiled binary (Go, Rust, native) | Rebuild — sync alone gains nothing |
| Dockerfile, `package.json`, `go.mod` | Rebuild — these *should* invalidate the layer cache |
| Sidecar process or container in the pod | Rebuild that artifact; sync doesn't touch sibling containers automatically |
| Kubernetes manifests / Helm values | Skaffold re-renders + re-applies; no rebuild needed |

## Don't / Do

| Don't | Do |
|---|---|
| `sync.infer:` against multi-stage Dockerfile | `sync.manual:` with explicit `src`/`dest`/`strip` |
| Forget `strip:` and wonder why files land deep | `strip:` to match what `COPY` did at build time |
| Sync source for a compiled language | Rebuild — it's likely as fast as a synced restart |
| Roll your own restart-on-sync logic outside Skaffold | `sync.hooks.after.container` with the framework's reload signal |
| Hooks doing heavy work on `before` build | Codegen yes, full test suites no — runs every loop iteration |
| `container:` hooks calling tools not in the image | Use `kill`/shell builtins or bake the tool in for dev |
| Sync the entire repo into the container | Narrow patterns; sync is for the small fast-iteration surface, not your whole tree |
