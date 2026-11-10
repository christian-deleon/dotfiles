# MCP Server Entries

**MCP (Model Context Protocol)** is the standard for connecting external tools and data sources to AI agents. An MCP server entry tells the agent: "here's a process to spawn (or URL to reach), here's how to authenticate, here are the tools it exposes."

Two inputs decide what runs:

- **Roster** — `~/.dotfiles/ai/mcp-servers.json.tpl`: every server this repo knows how to launch.
- **Active profile's `mcp:` block** — `mcp.enable: [...]` picks servers; `mcp.override.<server>` patches launch fields. With no profile or no block, the roster's `"default": true` servers (context7, firecrawl) run.

`generate_mcp_configs()` applies overrides, resolves `op://` secrets (1Password) for the enabled servers only, and writes exactly that set to every enabled harness:

| Harness | Path | Notes |
|---|---|---|
| Grok | live `~/.grok/config.toml` `[mcp_servers.*]` | Via `merge-grok-mcp.py`, which also drops those names from `[tools] disabled_mcp_servers` |
| OpenCode | `~/.config/opencode/opencode.json` `mcp.servers` | Converted shape (see below) |
| Claude Code | `~/.claude.json` `mcpServers` | Roster names not enabled are removed; hand-added non-roster servers, OAuth, and UI keys stay |

The most common AI failure mode is editing `~/.grok/config.toml` MCP tables, `opencode.json`, or `~/.claude.json` by hand, or toggling a server in a harness UI — the next regen resets it. Change the profile instead.

## Source of truth

```
~/.dotfiles/ai/mcp-servers.json.tpl
```

Format: a JSON object, one key per server. Author `command` / `args` / `env` / `url` / `headers` — the installer converts to Grok TOML, OpenCode JSON, and Claude JSON. `"default": true` marks a server enabled when no profile `mcp:` block exists.

```json
{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp", "--api-key", "op://vault/item/credential"],
    "description": "Live documentation lookup"
  },
  "example-stdio": {
    "command": "npx",
    "args": ["-y", "example-mcp-server"],
    "env": {
      "EXAMPLE_API_TOKEN": "op://vault/item/token"
    },
    "description": "Stdio server with a 1Password secret"
  },
  "remote-api": {
    "type": "http",
    "url": "https://api.example.com/mcp",
    "headers": {
      "Authorization": "Bearer op://vault/item/token"
    },
    "description": "Remote HTTP transport example"
  }
}
```

## Generated targets

`dot mcp-regen` forces a run; post_install on `grok` / `opencode` / `claude` runs it too. The hash at `~/.cache/dotfiles/mcp-servers.hash` covers the roster, the profile `mcp:` block, and the enabled harness list; a run is skipped when it matches and every harness still has the servers listed in `~/.cache/dotfiles/<harness>-mcp-servers` (names last written; servers dropped for a missing secret don't count). `FORCE_MCP_REGEN=true` bypasses the cache.

## Profile `mcp:` block

```yaml
# profiles/wsl-work.yaml
mcp:
  enable: [context7, firecrawl, kubernetes]
  override:
    kubernetes:
      command: kubernetes-mcp-server   # Ubuntu npm wedges `npx @latest`
```

- `enable` — roster names; unknown names warn and are ignored.
- `override.<server>` — any of `command`, `args`, `env`, `url`, `headers`, `type`. A `command` without `args` drops the roster's args. Applied before 1Password injection and `$HOME` expansion.

Personal profiles enable aws, context7, firecrawl, flux, gitea, grafana, kubernetes, playwright.

## Docs / web split (current roster)

Do **not** stack multiple general-purpose search servers. The intentional pair:

| Server | Role |
|---|---|
| `context7` | Library/SDK/framework package docs (RAG over curated indexes) |
| `firecrawl` | Open-web search, scrape known URLs, multi-page research |

Domain servers own their own docs when relevant (`aws` docs tools, `flux` docs search). Routing for agents lives in `ai/rules/common/prefer-mcp.md` — keep that rule and this table aligned when you add or remove a docs/web server.

**Default-enabled** (`"default": true` in the roster): only `context7` and `firecrawl`. Profiles with an `mcp:` block list their servers explicitly, so a new server reaches a machine only when its profile's `mcp.enable` names it.

## Server schema (roster JSON)

### stdio (local process — most common)

```json
{
  "server-name": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-foo"],
    "env": {
      "API_KEY": "op://vault/item/credential",
      "STATIC_VAR": "value"
    },
    "description": "Optional human-readable description"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `command` | yes (stdio) | Executable name or absolute path |
| `args` | no | Array of strings |
| `env` | no | Map of env vars (1Password refs OK) |
| `description` | no | Convention; surfaces in some UIs |
| `type` | no | Default `stdio`; set `http` / `sse` / `streamable-http` for remote |

### http (remote, streamable)

```json
{
  "server-name": {
    "type": "http",
    "url": "https://mcp.example.com",
    "headers": {
      "Authorization": "Bearer op://vault/item/token"
    },
    "description": "..."
  }
}
```

Grok writes this as `[mcp_servers.name]` with `url` / `headers` / `enabled`. OpenCode writes `type: "remote"`; Claude writes `type: "http"` (or `"sse"`).

## 1Password secret injection

Any value (in `args`, `env`, or `headers`) can be a 1Password CLI reference:

```
op://<vault>/<item>/<field>
```

Secrets are pulled at generate time, only for enabled servers, and written as plaintext into the **live** Grok config, OpenCode `opencode.json`, and `~/.claude.json` (mode 600). Never into the tracked seed `grok/.grok/config.toml`. Sign into 1Password before `dot mcp-regen`.

```json
"EXAMPLE_API_TOKEN": "op://<vault>/<item>/<field>"
```

To find a vault/item ID: `op item list --format=json | jq '.[] | {title, id}'`.

## OpenCode conversion

| Roster field | OpenCode field |
|---|---|
| server key | `mcp.servers.<name>` (OpenCode 2; not a top-level `mcp.<name>`) |
| `type: "stdio"` (or omitted) | `type: "local"` |
| `type: "http"` / `"sse"` | `type: "remote"` |
| `command: "npx"` + `args: [...]` | `command: ["npx", ...]` (single array) |
| `env: {...}` | `environment: {...}` |
| `headers` / `url` | same |

Servers not enabled are not written. Author the template in the roster shape — don't mix in harness keys.

## Adding a new MCP server

1. Open `~/.dotfiles/ai/mcp-servers.json.tpl`.
2. Add the entry (roster shape, `op://` for secrets).
3. `jq . ~/.dotfiles/ai/mcp-servers.json.tpl`.
4. Add the name to `mcp.enable` in each profile that should run it (or `"default": true` for profile-less machines).
5. `dot mcp-regen`.
6. Restart the harnesses. `grok inspect` — source should be `config`; `claude mcp list`.

## Removing or disabling

- **Disable on a machine class:** drop the name from that profile's `mcp.enable`. The next regen removes it from every harness.
- **Remove entirely:** delete the roster entry and its `mcp.enable` mentions.

Machine-class launch differences (work WSL vs personal) go in the profile's `mcp.override`, not in `grok/.grok/overlays/` — overlay MCP tables are ignored with a warning.

## Common patterns

### npm-based server with secret

```json
"firecrawl": {
  "command": "npx",
  "args": ["-y", "firecrawl-mcp"],
  "env": {
    "FIRECRAWL_API_KEY": "op://vault/item/credential"
  },
  "description": "Web search, scrape, and research"
}
```

### Managed AWS MCP via SigV4 proxy (full access)

Grok namespaces tools as `server__tool` and drops the managed server's `aws___call_aws` names (session registers 0 tools; `grok mcp doctor` still counts 9). The shim rewrites `aws___foo` → `foo` on `tools/list` and maps `tools/call` back.

```json
"aws": {
  "command": "python3",
  "args": [
    "$HOME/.dotfiles/ai/scripts/aws_mcp_grok_shim.py",
    "uvx",
    "mcp-proxy-for-aws@1.6.4",
    "https://aws-mcp.us-east-1.api.aws/mcp",
    "--metadata",
    "AWS_REGION=us-east-1"
  ],
  "description": "AWS API, docs, and skills (managed; shim strips aws___ names for Grok)"
}
```

Pin the proxy version. Do **not** re-add `--read-only` unless intentionally hiding write tools — agent policy (skill + `rules/common/live-mutations.md`) enforces read-default behavior instead.

### Docker-based local MCP server

```json
"example-docker": {
  "command": "docker",
  "args": [
    "run",
    "-i",
    "--rm",
    "example/mcp-server:1.0.0"
  ],
  "description": "Containerised stdio server"
}
```

### Server pinned to a local mise shim

```json
"grafana": {
  "command": "/home/cdeleon/.local/share/mise/shims/uvx",
  "args": ["mcp-grafana"],
  "env": {
    "GRAFANA_URL": "https://grafana.example.com",
    "GRAFANA_SERVICE_ACCOUNT_TOKEN": "op://vault/item/credential"
  },
  "description": "Grafana dashboards"
}
```

Use absolute mise shims when the server needs a specific Python/uv. Bare `uvx` works if mise is on `PATH` in the process that starts Grok.

## Per-tool gotchas

### Grok
- Written to live `~/.grok/config.toml`. `grok inspect` shows source `config`.
- `/mcps` toggles at runtime, and Grok records them in `[tools] disabled_mcp_servers`; the next regen takes enabled names back out.
- Claude compat MCP scan is **off** (`[compat.claude] mcps = false`).

### OpenCode
- Servers live under `mcp.servers`. Do not write `enabled`.
- `timeout` objects (startup/catalog/execution) are supported but not emitted by our generator.
- `oauth` on remote servers exists; rarely needed.

### Claude Code
- User-scope servers live in `~/.claude.json` `mcpServers`; stdio entries get `type: "stdio"`.
- Running sessions rewrite that file; the generator gives up (rerun `dot mcp-regen`) rather than clobber a concurrent write.

## After authoring

1. `jq . ~/.dotfiles/ai/mcp-servers.json.tpl`
2. `dot mcp-regen`
3. Restart the harnesses. `grok inspect` / `claude mcp list` to confirm registration.
4. If 1Password isn't signed in: `op signin`, then `dot mcp-regen` again.
