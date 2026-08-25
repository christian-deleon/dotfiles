# MCP Server Entries

**MCP (Model Context Protocol)** is the standard for connecting external tools and data sources to AI agents. An MCP server entry tells the agent: "here's a process to spawn (or URL to reach), here's how to authenticate, here are the tools it exposes."

This repo treats `~/.dotfiles/ai/mcp-servers.json.tpl` as the **single source of truth**. `generate_mcp_configs()` reads the template, injects secrets via `op://` (1Password), and writes:

| Target | Path | Role |
|---|---|---|
| Grok | live `~/.grok/config.toml` `[mcp_servers.*]` | Canonical |
| OpenCode | `~/.config/opencode/opencode.json` `mcp` | Adapter (JSON ≠ TOML) |

Don't edit the live files. Don't write `~/.claude.json`. The most common AI failure mode is editing `~/.grok/config.toml` MCP tables or `opencode.json` by hand — the next `dot mcp-regen` overwrites them.

## Source of truth

```
~/.dotfiles/ai/mcp-servers.json.tpl
```

Format: a JSON object, one key per server. Author `command` / `args` / `env` / `url` / `headers` — the installer converts to Grok TOML and OpenCode JSON.

```json
{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp", "--api-key", "op://vault/item/credential"],
    "description": "Live documentation lookup"
  },
  "github": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-github"],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "op://vault/item/token"
    },
    "description": "GitHub operations - PRs, issues, repos"
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

`dot mcp-regen` (or post_install on `grok` / `opencode`). Hash cache at `~/.cache/dotfiles/mcp-servers.hash` skips regeneration when the template is unchanged **and** live Grok `config.toml` already has `[mcp_servers.` tables. Set `FORCE_MCP_REGEN=true` to bypass.

## Docs / web split (current roster)

Do **not** stack multiple general-purpose search servers. The intentional pair:

| Server | Role |
|---|---|
| `context7` | Library/SDK/framework package docs (RAG over curated indexes) |
| `firecrawl` | Open-web search, scrape known URLs, multi-page research |

Domain servers own their own docs when relevant (`terraform` registry, `aws` docs tools, `flux` docs search). Routing for agents lives in `ai/rules/common/prefer-mcp.md` — keep that rule and this table aligned when you add or remove a docs/web server.

**Default-enabled** (see `enabled_mcp_servers` in `scripts/handlers/ai.sh`): only `context7` and `firecrawl`. Everything else is installed with `enabled = false`. When adding a server you expect always-on, update that list too.

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

Grok writes this as `[mcp_servers.name]` with `url` / `headers` / `enabled`. OpenCode writes `type: "remote"`.

## 1Password secret injection

Any value (in `args`, `env`, or `headers`) can be a 1Password CLI reference:

```
op://<vault>/<item>/<field>
```

Secrets are pulled at generate time and written as plaintext into the **live** Grok config and OpenCode `opencode.json` (mode 600). Never into the tracked seed `grok/.grok/config.toml`. Sign into 1Password before `dot mcp-regen`.

```json
"GITHUB_PERSONAL_ACCESS_TOKEN": "op://ujvoilqaehz2gozzpp2jqyhxsu/lcpymvki7xwdbvucadxiy2ukpa/token"
```

To find a vault/item ID: `op item list --format=json | jq '.[] | {title, id}'`.

## OpenCode conversion (adapter)

| Roster field | OpenCode field |
|---|---|
| `type: "stdio"` (or omitted) | `type: "local"` |
| `type: "http"` / `"sse"` | `type: "remote"` |
| `command: "npx"` + `args: [...]` | `command: ["npx", ...]` (single array) |
| `env: {...}` | `environment: {...}` |
| `headers` / `url` | same |

Author the template in the roster shape — don't mix in OpenCode keys.

## Adding a new MCP server

1. Open `~/.dotfiles/ai/mcp-servers.json.tpl`.
2. Add the entry (roster shape, `op://` for secrets).
3. `jq . ~/.dotfiles/ai/mcp-servers.json.tpl`.
4. If it should be always-on, add the name to `enabled_mcp_servers` in `scripts/handlers/ai.sh`.
5. `dot mcp-regen`.
6. Restart Grok (and OpenCode if you care). `grok inspect` — source should be `config`.

## Removing or disabling

1. **Delete the entry** from the template. Next generate drops it.
2. **Rename the key** e.g. `"github"` → `"_disabled_github"` (JSON has no comments). The installer still writes it; it won't be picked up by the old name.

Don't edit live `config.toml` MCP tables as the long-term fix — `merge-grok-mcp.py` replaces `[mcp_servers.*]` on the next regen. Servers already `enabled = true` in the live file stay enabled (unioned with `enabled_mcp_servers`).

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
"terraform": {
  "command": "docker",
  "args": [
    "run",
    "-i",
    "--rm",
    "hashicorp/terraform-mcp-server:1.1.0"
  ],
  "description": "HashiCorp Terraform Registry MCP"
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
- Canonical write is live `~/.grok/config.toml`. `grok inspect` shows source `config`.
- `/mcps` toggles at runtime. `disabled_mcp_servers` in `[tools]` is a leftover key Grok currently flags as unrecognized — prefer per-server `enabled = false` from the generator.
- Claude compat MCP scan is **off** (`[compat.claude] mcps = false`).

### OpenCode
- `enabled: false` on a server entry disables it without removing config.
- `timeout: 5000` (milliseconds) per server is supported but not emitted by our generator.
- `oauth` on remote servers exists; rarely needed.

## After authoring

1. `jq . ~/.dotfiles/ai/mcp-servers.json.tpl`
2. `dot mcp-regen`
3. Restart Grok. `grok inspect` to confirm registration.
4. If 1Password isn't signed in: `op signin`, then `dot mcp-regen` again.
