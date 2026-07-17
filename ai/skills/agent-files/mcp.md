# MCP Server Entries

**MCP (Model Context Protocol)** is the standard for connecting external tools and data sources to AI agents. An MCP server entry tells the agent: "here's a process to spawn (or URL to reach), here's how to authenticate, here are the tools it exposes." All three tools speak MCP, but their config shapes differ.

This repo treats `~/.dotfiles/ai/mcp-servers.json.tpl` as the **single source of truth** for MCP servers across Claude Code, OpenCode, and Grok. The installer's `generate_mcp_configs()` function reads the template, injects secrets via `op://` references (1Password), and writes per-tool config files. Don't edit the per-tool configs directly — your changes will be overwritten on next install.

The most common AI failure mode is editing `~/.claude.json` or `~/.config/opencode/opencode.json` directly. Those are generated files. Edit the template.

## Source of truth

```
~/.dotfiles/ai/mcp-servers.json.tpl
```

Format: a JSON object where each key is a server name and each value is a server definition. **Use the Claude-Desktop / Claude-Code shape** — the installer converts it to OpenCode's shape automatically.

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

Run `dot mcp-regen` (or `FORCE_MCP_REGEN=true` with `dot install claude`/`opencode` to bypass the hash cache). The installer writes:

| Target | Path | Format |
|---|---|---|
| Claude Code | `~/.claude.json` under `mcpServers` | Claude shape (same as template) |
| OpenCode | `~/.config/opencode/opencode.json` under `mcp` | OpenCode shape (converted) |
| Grok | reads `~/.claude.json` via compat | (no separate write) |

The hash cache at `~/.cache/dotfiles/mcp-servers.hash` skips regeneration when the template hasn't changed AND target files exist with non-empty `mcpServers`. Set `FORCE_MCP_REGEN=true` to bypass.

## Docs / web split (current roster)

Do **not** stack multiple general-purpose search servers. The intentional pair:

| Server | Role |
|---|---|
| `context7` | Library/SDK/framework package docs (RAG over curated indexes) |
| `firecrawl` | Open-web search, scrape known URLs, multi-page research |

Domain servers own their own docs when relevant (`terraform` registry, `aws` docs tools, `flux` docs search). Routing for agents lives in `ai/rules/common/prefer-mcp.md` — keep that rule and this table aligned when you add or remove a docs/web server.

**Default-enabled** (see `enabled_mcp_servers` in `scripts/handlers/ai.sh`): only `context7` and `firecrawl`. Everything else in the template is installed but disabled until the user enables it per session. When adding a server you expect always-on, update that list too.

## Server schema (template = Claude shape)

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
| `type` | no | Default `stdio`; set explicitly for http/sse |

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

`type` can also be `"streamable-http"` (alias) or `"sse"` (older SSE transport).

## 1Password secret injection

Any value (in `args`, `env`, or `headers`) can be a 1Password CLI reference:

```
op://<vault>/<item>/<field>
```

The installer runs `op inject` against the template before writing the per-tool configs. Secrets are pulled at install time, written as plaintext to the generated configs (which live in `~/.claude.json` / `~/.config/opencode/opencode.json`). Make sure the user is signed into 1Password before `dot mcp-regen` / AI install — the installer prompts otherwise.

Common patterns from `mcp-servers.json.tpl`:

```json
"GITHUB_PERSONAL_ACCESS_TOKEN": "op://ujvoilqaehz2gozzpp2jqyhxsu/lcpymvki7xwdbvucadxiy2ukpa/token"
```

To find a vault/item ID: `op item list --format=json | jq '.[] | {title, id}'`.

## OpenCode conversion

OpenCode's MCP shape differs from Claude's:

| Claude field | OpenCode field |
|---|---|
| `type: "stdio"` | `type: "local"` |
| `type: "http"` / `"sse"` | `type: "remote"` |
| `command: "npx"` + `args: [...]` | `command: ["npx", ...]` (single array) |
| `env: {...}` | `environment: {...}` |
| `headers: {...}` | `headers: {...}` (same) |
| `url: "..."` | `url: "..."` (same) |

The installer handles this conversion automatically. **Author the template in Claude shape** — don't try to mix in OpenCode keys.

## Adding a new MCP server

1. Open `~/.dotfiles/ai/mcp-servers.json.tpl`.
2. Add the new server entry (Claude shape, with `op://` references for any secrets).
3. Validate the JSON: `jq . ~/.dotfiles/ai/mcp-servers.json.tpl`.
4. Run `dot mcp-regen` to regenerate configs immediately.
5. Restart any running Claude Code / OpenCode / Grok session — MCP servers are loaded on session start.

## Removing or disabling an MCP server

Two options:

1. **Delete the entry** from the template. The next install regenerates without it.
2. **Comment it out** by renaming the key, e.g. `"github"` → `"_disabled_github"`. JSON has no native comments — this is the dotfiles convention. The server still gets written to disk but won't be picked up by name.

To make a one-off, machine-specific change without touching dotfiles: edit `~/.claude.json` directly **and** delete the hash cache (`rm ~/.cache/dotfiles/mcp-servers.hash`) — but be aware your edit will be overwritten on next install if the template hasn't also changed.

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

```json
"aws": {
  "command": "uvx",
  "args": [
    "mcp-proxy-for-aws@1.6.3",
    "https://aws-mcp.us-east-1.api.aws/mcp",
    "--metadata",
    "AWS_REGION=us-east-1"
  ],
  "description": "AWS API, docs, and skills (managed; full access — agents read-only by policy)"
}
```

Pin the proxy version (supply-chain hygiene). Do **not** re-add `--read-only`
unless intentionally hiding write tools — agent policy (skill +
`rules/common/live-mutations.md`) enforces read-default behavior instead.

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

Use absolute paths to mise shims when the server needs a specific Python or uv version. Bare `uvx` works if mise's `PATH` is set up correctly in the shell that spawns the MCP client.

## Per-tool gotchas

### Claude Code
- `mcpServers` in `~/.claude.json` is user-level; `.mcp.json` at a repo root is project-level (team-shared).
- Local-scope MCP (project-specific, private) goes under `projects.<path>.mcpServers` in `~/.claude.json` — the installer doesn't touch that.
- `claude mcp add` / `claude mcp list` CLI commands manage user-scope; don't use them for dotfiles-managed servers.

### OpenCode
- `enabled: false` on a server entry disables it without removing config — useful for keeping a definition around but turning it off temporarily.
- `timeout: 5000` (milliseconds) per server.
- The `oauth` block on remote servers is supported but rarely needed.

### Grok
- Reads `~/.claude.json` via compat. No separate file generated.
- Use `grok inspect` to confirm which servers loaded and from where.
- The `/mcps` modal manages servers interactively at runtime.

## After authoring

1. `jq . ~/.dotfiles/ai/mcp-servers.json.tpl` to validate.
2. `dot mcp-regen` to regenerate.
3. Restart Claude Code / OpenCode / Grok sessions — MCP servers load at session start.
4. Test the new tools: in Claude Code, ask the agent to call one; in Grok, use `grok inspect` to confirm registration.

If 1Password isn't signed in: the installer warns and skips injection. Run `op signin`, then re-run `dot mcp-regen`.
