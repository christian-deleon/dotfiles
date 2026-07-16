---
name: terraform-mcp
description: Terraform Registry and HCP/TFE access via the HashiCorp `terraform` MCP server. Use when looking up current provider docs, module inputs/outputs, Sentinel policies, or HCP Terraform/TFE workspaces — 'what args does this module take', 'search the registry for an EKS module', 'explain this plan'. Prefer over training-data recall for provider/module facts.
compatibility: opencode
---

# Terraform MCP Usage

Registry and (when configured) HCP Terraform / Terraform Enterprise interaction goes through the HashiCorp **`terraform`** MCP server (`hashicorp/terraform-mcp-server`). Prefer it over guessing provider schemas or scraping docs by hand.

This skill governs the **MCP server**. For authoring HCL (modules, state, OpenTofu defaults), use the [[terraform]] skill.

## If the MCP server is not enabled

If `terraform` MCP tools are not available, **stop and ask the user to enable the `terraform` MCP server** before proceeding. Do not invent provider argument names from memory when a live registry lookup would answer the question.

## What it's for

- Current **provider documentation** (resources, data sources, arguments)
- **Module** discovery and inputs/outputs/examples from the public registry
- **Sentinel** / policy lookups when relevant
- **HCP Terraform / TFE** workspace listing and ops — only if `TFE_TOKEN` / `TFE_ADDRESS` are configured for the server

This install runs the official Docker image in stdio mode **without** HCP/TFE credentials by default (public registry tools only). To enable private registry / workspace tools, add env to the `terraform` entry in `ai/mcp-servers.json.tpl` (`TFE_TOKEN`, `TFE_ADDRESS`) and regenerate MCP configs.

## Mutation posture

Workspace create/update/delete and run-triggering tools are powerful. Do **not** call any mutating HCP/TFE operation unless the user has **explicitly authorized that specific action** in the current conversation. Prefer read/search tools for day-to-day authoring help.

## Do not

- Treat MCP output as applied infrastructure — registry docs are source of truth for *schemas*, not for what is running in an account
- Use this as a substitute for `tofu plan` / `tofu apply` in the user's workspace
- Reach for Context7 or Firecrawl for provider/module schemas when this server is available
