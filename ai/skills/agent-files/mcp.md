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

Run `dot install` (or `FORCE_MCP_REGEN=true dot install` to bypass the hash cache). The installer writes:

| Target | Path | Format |
|---|---|---|
| Claude Code | `~/.claude.json` under `mcpServers` | Claude shape (same as template) |
| OpenCode | `~/.config/opencode/opencode.json` under `mcp` | OpenCode shape (converted) |
| Grok | reads `~/.claude.json` via compat | (no separate write) |

The hash cache at `~/.cache/dotfiles/mcp-servers.hash` skips regeneration when the template hasn't changed AND target files exist with non-empty `mcpServers`. Set `FORCE_MCP_REGEN=true` to bypass.

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

The installer runs `op inject` against the template before writing the per-tool configs. Secrets are pulled at install time, written as plaintext to the generated configs (which live in `~/.claude.json` / `~/.config/opencode/opencode.json`). Make sure the user is signed into 1Password before `dot install` — the installer prompts otherwise.

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
4. Run `FORCE_MCP_REGEN=true dot install` to regenerate configs immediately.
5. Restart any running Claude Code / OpenCode / Grok session — MCP servers are loaded on session start.

## Removing or disabling an MCP server

Two options:

1. **Delete the entry** from the template. The next install regenerates without it.
2. **Comment it out** by renaming the key, e.g. `"github"` → `"_disabled_github"`. JSON has no native comments — this is the dotfiles convention. The server still gets written to disk but won't be picked up by name.

To make a one-off, machine-specific change without touching dotfiles: edit `~/.claude.json` directly **and** delete the hash cache (`rm ~/.cache/dotfiles/mcp-servers.hash`) — but be aware your edit will be overwritten on next install if the template hasn't also changed.

## Common patterns

### npm-based server with secret

```json
"brave-search": {
  "command": "npx",
  "args": ["-y", "@brave/brave-search-mcp-server"],
  "env": {
    "BRAVE_API_KEY": "op://vault/item/credential"
  },
  "description": "Web search via Brave"
}
```

### uvx / Python-based server with read-only mode

```json
"aws-api": {
  "command": "uvx",
  "args": ["awslabs.aws-api-mcp-server@latest"],
  "env": {
    "READ_OPERATIONS_ONLY": "true",
    "REQUIRE_MUTATION_CONSENT": "true"
  },
  "description": "AWS API access (read-only by default)"
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
2. `FORCE_MCP_REGEN=true dot install` to regenerate.
3. Restart Claude Code / OpenCode / Grok sessions — MCP servers load at session start.
4. Test the new tools: in Claude Code, ask the agent to call one; in Grok, use `grok inspect` to confirm registration.

If 1Password isn't signed in: the installer warns and skips injection. Run `op signin`, then re-run `dot install`.
