---
name: playwright-mcp
description: Browser automation via the Playwright MCP server. Use when driving a browser, taking UI screenshots, verifying a web UI, or using browser_* tools — 'open this page', 'screenshot the chart', 'click through the login'. Screenshots must not land in the project tree.
compatibility: opencode
---

# Playwright MCP Usage

Browser automation goes through the **`playwright`** MCP server. Prefer its tools over Bash/`npx playwright`.

If the tools are not available, ask the user to enable the `playwright` MCP server — do not invent a fallback.

## Profile

Uses a **separate** Chromium user-data dir: `~/.config/chromium-agent`. That is a full second browser (extensions, 1Password, cookies), not a picker profile inside daily Chromium, so it can run while Work / other profiles stay open.

Open it yourself to install extensions or log in:

```bash
chromium-agent
```

Walker: **Chromium Agent**. Windows use class `chromium-agent` and Hyprland floats them (1300×1500, not pinned) so they overlay the workspace they opened on. Playwright launches with `--sandbox` so Chromium does not show the unsupported `--no-sandbox` infobar.

Same-dir lock: only one process can hold `~/.config/chromium-agent`. Do not point `--user-data-dir` back at `~/.config/chromium`.

## Shared browser — wait your turn

The Agent profile is **one** Chromium. Another agent may already own it. Do **not**:

- close it (`browser_close`, `pkill`/`kill`, Hyprland close)
- steal it with a new tab or a second instance
- retry in a loop

If launch fails because the profile is in use, **stop and ask the user** to let you proceed. Wait until they say you can. Do not assume you may close the other session or take the window.

## Screenshots must not land in the project

`--output-dir` is `/tmp/playwright-mcp`, but that only applies when `filename` is **omitted**. A bare name (e.g. `chart.png`) is resolved against the **project workspace** and leaves untracked files in the repo.

| `filename` | Where it is written |
|---|---|
| *(omit)* | `/tmp/playwright-mcp/page-….png` |
| `foo.png` | project cwd — **never** |
| `/tmp/playwright-mcp/foo.png` | output dir (only if a stable name is required) |

Same rule for other tools that accept `filename` (PDF, snapshot-to-file, console/network dumps): omit, or absolute under `/tmp/playwright-mcp/`.

Do not leave browser artifacts in the working tree unless the user explicitly asked for an in-repo file.

## Snapshot vs screenshot

- **Act** on the page (click, fill, inspect structure) → `browser_snapshot`
- **See** pixels → `browser_take_screenshot` with no bare `filename`
