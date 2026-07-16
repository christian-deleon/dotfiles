---
name: aws-mcp
description: AWS API access via the `aws` MCP server (mcp-proxy-for-aws). Use whenever a task requires reading live AWS state (S3, EC2, IAM, Lambda, CloudWatch, RDS, EKS), current AWS docs, or state-of-the-cloud questions — 'what's in this bucket', 'who has access to X', 'list my instances'. Read-only by default.
compatibility: opencode
---

# AWS MCP Usage

All AWS API access goes through the **`aws`** MCP server (reached via `mcp-proxy-for-aws` → `https://aws-mcp.us-east-1.api.aws/mcp`). Do not shell out to the `aws` CLI via Bash for AWS API calls.

## If the MCP server is not enabled

If `aws` MCP tools are not available, **stop and ask the user to enable the `aws` MCP server** before proceeding. Do not fall back to running `aws` via Bash, and do not try to construct API calls another way.

## Prefer goals over hardcoded API steps

Describe the outcome ("list untagged EC2 instances in this account") and let the agent pick tools. Prefer composing multi-step work with the script tool rather than a long chain of one-shot API calls.

| Tool family (names may vary by client prefix) | Use for |
|---|---|
| `call_aws` / `aws___call_aws` | Single authenticated AWS API/CLI-equivalent call |
| `run_script` / `aws___run_script` | Multi-step logic in one sandboxed pass (list → filter → act) |
| `search_documentation` / `read_documentation` | Current AWS docs (not training-data recall) |
| `retrieve_skill` | Curated AWS procedures from the managed server |
| `list_regions` / `get_regional_availability` | Region and feature availability |

## Read-only by default

This install pins the proxy with **`--read-only`**, so write-capable tools should not be exposed. Still treat any mutation as unauthorized unless the user has **explicitly authorized that specific change in the current conversation**. A general "go ahead" is not enough.

When in doubt, treat the action as a mutation and ask first.

## Auth and region

- Credentials: local AWS credential chain (`aws configure` / `aws login` / env / SSO). The proxy SigV4-signs requests to the managed endpoint.
- Default operation region in this config: **`us-east-1`** (`--metadata AWS_REGION=us-east-1`). The endpoint host region (`us-east-1` in the URL) is where the MCP service runs; it can differ from the operation region if you later change metadata.
- Profile switching: proxy supports `--profile` if multi-account work needs it — only change the template when the user asks.

## Do not

- Fall back to Bash `aws` when the MCP server is simply disabled (ask the user to enable it)
- Use Context7 or Firecrawl for AWS service docs when this server's documentation tools are available
