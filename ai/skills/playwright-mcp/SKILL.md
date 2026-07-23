---
name: playwright-mcp
description: Browser automation via the Playwright MCP server. Use when driving a browser, taking UI screenshots, verifying a web UI, or using browser_* tools — 'open this page', 'screenshot the chart', 'click through the login'. Screenshots must not land in the project tree.
compatibility: opencode
---

# Playwright MCP Usage

Browser automation goes through the **`playwright`** MCP server. Prefer its tools over Bash/`npx playwright`.

If the tools are not available, ask the user to enable the `playwright` MCP server — do not invent a fallback.

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
