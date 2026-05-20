# Skaffold Debug

`skaffold debug` is not "verbose dev." It rewrites the pod's container entrypoint to launch the runtime under a language-specific debugger, exposes the debugger's port, auto-port-forwards it to localhost, and then tails logs the same as `dev`. Your IDE attaches to `localhost:<port>` and you have breakpoints in a pod running in a real cluster.

If you're reaching for `kubectl debug` ephemeral containers in a Skaffold project, you've taken a wrong turn. Use `skaffold debug`.

## Supported runtimes

Skaffold's `debug-helper` images ship the debuggers. The init container injects them at deploy time when Skaffold detects a supported runtime:

| Language | Debugger | Default port | Detection signal |
|---|---|---|---|
| Go | `dlv` (Delve) | 56268 | Image has Go binary; presence of `go` runtime markers |
| Node | V8 inspector | 9229 | `node` in image entrypoint or `package.json` |
| Python | `debugpy` | 5678 | `python`/`python3` in entrypoint |
| Java | JDWP | 5005 | `java` in entrypoint or JVM image |
| .NET | `vsdbg` | 5050 | `dotnet` in entrypoint |

Detection failures are the most common cause of `skaffold debug` "not working" — Skaffold falls back silently to a normal deploy. Run `skaffold debug --auto-init=true --auto-build=true -vdebug` and look for the `Debugging support for ... not enabled` log line.

## How the rewrite works

Skaffold mutates the deployed PodSpec at render time:

1. **Adds an init container** that copies the debugger binary from the `debug-helpers` image into a shared volume.
2. **Mounts the shared volume** into your app container at `/dbg`.
3. **Rewrites the container's `command:` and `args:`** to launch via the debugger (e.g. `dlv --listen :56268 --headless ... exec /your-binary`).
4. **Adds a `containerPort:`** for the debugger port.
5. **Adds the port to Skaffold's port-forward set**, so it appears on localhost automatically.
6. **Annotates the pod** with `debug.cloud.google.com/config` describing what was rewritten — useful for inspection.

If your Helm chart hardcodes `command:` and `args:`, Skaffold's rewrite still wins because the mutation happens after rendering. If your chart sets `securityContext.readOnlyRootFilesystem: true`, the rewrite fails — relax it for the debug profile.

## Per-language deep

### Go (Delve)

```yaml
profiles:
  - name: debug
    activation:
      - command: debug
    patches:
      - op: replace
        path: /build/artifacts/0/ko/ldflags
        value: []                                     # drop `-s -w`
      - op: add
        path: /build/artifacts/0/ko/flags
        value:
          - -gcflags=all=-N -l                        # no inlining, no optimization
```

Without `-gcflags=all=-N -l`, breakpoints land on the wrong lines because the compiler inlined and optimized. The `debug` profile pattern above is essentially required for Go.

VS Code `launch.json`:

```json
{
  "name": "Skaffold: attach to Go pod",
  "type": "go",
  "request": "attach",
  "mode": "remote",
  "remotePath": "${workspaceFolder}",
  "port": 56268,
  "host": "127.0.0.1",
  "substitutePath": [
    { "from": "${workspaceFolder}", "to": "/ko-app" }
  ]
}
```

`substitutePath` is the trick — Delve sees paths as the container saw them at build time (`/ko-app/...`), but breakpoints come from your local source tree.

GoLand: Run → Edit Configurations → Go Remote → Host `localhost`, Port `56268`.

### Node (V8 inspector)

```yaml
profiles:
  - name: debug
    activation:
      - command: debug
    patches:
      - op: replace
        path: /build/artifacts/0/docker/target
        value: dev                                    # multi-stage `dev` target with dev deps
```

VS Code:

```json
{
  "name": "Skaffold: attach to Node pod",
  "type": "node",
  "request": "attach",
  "port": 9229,
  "address": "localhost",
  "localRoot": "${workspaceFolder}",
  "remoteRoot": "/app",
  "skipFiles": ["<node_internals>/**"]
}
```

`localRoot` / `remoteRoot` map your local tree to the container's filesystem. Use `--inspect-brk` if you want the process to pause until you attach (good for crashes on startup); plain `--inspect` doesn't pause.

For TypeScript, source-map support is automatic if `.js.map` files are next to the `.js` files in the container. Don't tree-shake source maps out of the dev image.

### Python (debugpy)

```yaml
profiles:
  - name: debug
    activation:
      - command: debug
```

By default Skaffold launches under `debugpy --listen :5678 --wait-for-client`. The `--wait-for-client` is important: your process blocks until the IDE attaches. That's usually what you want — otherwise the process is past your initialization code before you can hit a breakpoint.

VS Code:

```json
{
  "name": "Skaffold: attach to Python pod",
  "type": "debugpy",
  "request": "attach",
  "connect": { "host": "localhost", "port": 5678 },
  "pathMappings": [
    { "localRoot": "${workspaceFolder}", "remoteRoot": "/app" }
  ],
  "justMyCode": false
}
```

`justMyCode: false` lets you step into library code (FastAPI, requests, etc.) — usually what you want for actual debugging.

### Java (JDWP)

```yaml
# No patches usually needed — Skaffold injects -agentlib:jdwp=... into JVM args
```

IntelliJ: Run → Edit Configurations → Remote JVM Debug → Host `localhost`, Port `5005`, Transport `Socket`, Debugger mode `Attach to remote JVM`.

VS Code (`Debugger for Java` extension):

```json
{
  "type": "java",
  "name": "Skaffold: attach to Java pod",
  "request": "attach",
  "hostName": "localhost",
  "port": 5005
}
```

For Spring Boot, also enable Spring Devtools — gets you live class reloading inside the running JVM via Jib's incremental layering.

### .NET (vsdbg)

```yaml
# No patches usually needed
```

VS Code: `Skaffold Debug` extension wires this automatically. Manual `launch.json` requires `pipeTransport` to exec `kubectl exec` and run `vsdbg` inside the pod — usually not worth the manual config; install the extension.

## Multi-container pods

When the pod has multiple containers (sidecars, init containers, service mesh proxies), Skaffold needs to know which one to attach the debugger to:

```yaml
profiles:
  - name: debug-api
    activation:
      - command: debug
    patches:
      # Without this, Skaffold tries to rewrite every container's entrypoint
      - op: add
        path: /build/artifacts/0/sync/manual/0/dest
        value: /app
```

Skaffold uses the **artifact-to-container mapping** from the rendered manifests: if a container's `image:` matches an artifact's `image:`, that container gets debug-rewritten. Sidecar containers with unrelated images are left alone. Verify by inspecting `kubectl get pod <name> -o yaml | grep -A1 command:` — only your artifact container should show the debugger entrypoint.

## Source-mapping pitfalls

Breakpoints not hitting, or hitting on wrong lines:

| Symptom | Cause | Fix |
|---|---|---|
| Breakpoints "grayed out" in IDE | Path mapping wrong | Set `localRoot`/`remoteRoot` (or `substitutePath` for Go) to match what's in the container |
| Breakpoint hits but variables show "optimized out" | Compiler stripped debug info | Build with debug flags (`-gcflags=all=-N -l` Go, `--target dev` Docker, etc.) |
| Process exits before debugger attaches | No wait-for-client | Use `debugpy ... --wait-for-client` (Python), `node --inspect-brk` (Node), JVM `suspend=y` |
| Breakpoint hits in dependencies, not your code | Source maps missing for TypeScript / sourcemaps disabled for Python | Ensure `.map` files in container; for Python, install `debugpy` not just `pydevd` |
| Hot-reload restarts the process and detaches the debugger | Framework's reloader respawns a new PID | Disable reloader during debug session, OR use a wait-for-client flag so each restart re-pauses |

## Augmenting the image yourself

For runtimes Skaffold doesn't natively support, or when you want a debugger Skaffold doesn't ship, add it to the image and use the regular `dev` command with `portForward:` for the debugger port:

```yaml
# Skip skaffold debug; do it manually
portForward:
  - resourceType: deployment
    resourceName: my-app
    port: 4000                                        # whatever your debugger listens on
    localPort: 4000
```

Then run `skaffold dev --port-forward` and attach your IDE to `localhost:4000`.

## Don't / Do

| Don't | Do |
|---|---|
| `kubectl debug` ephemeral containers for app-level debugging | `skaffold debug` — entrypoint rewrite + port-forward built in |
| Go binary built with `-s -w` for debugging | Drop optimization flags, add `-gcflags=all=-N -l`, in a `debug` profile |
| Debug-by-printf because "skaffold debug doesn't work" | Run `skaffold debug -vdebug` and check the `Debugging support for ... not enabled` line — it's usually a detection issue |
| Multi-container pod with all containers debug-rewritten | Skaffold scopes by artifact image — verify in the rendered PodSpec |
| `readOnlyRootFilesystem: true` in chart for debug profile | Relax it in the debug profile so init container can drop the debugger binary |
| Hardcode debugger port in chart values | Let Skaffold inject; `portForward:` picks it up automatically |
| Use `--inspect` (Node) when you need to debug startup | `--inspect-brk` to pause until attach |
| Use `debugpy` without `--wait-for-client` for startup bugs | Always `--wait-for-client` — initialization is half the bugs |
