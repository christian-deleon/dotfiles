---
name: aws-mcp
description: AWS API access via the `aws` MCP server (mcp-proxy-for-aws). Use for live AWS state (S3, EC2, IAM, Lambda, CloudWatch, RDS, EKS), current AWS docs, or account questions — 'what's in this bucket', 'who has access to X', 'list my instances'. Reads free; mutations need explicit per-action authorization.
compatibility: opencode
---

# AWS MCP Usage

All AWS API access goes through the **`aws`** MCP server (via `mcp-proxy-for-aws` → managed AWS MCP). Do not shell out to the `aws` CLI via Bash for API calls.

The proxy is **not** pinned `--read-only`. **Availability is not permission.** Mutation policy is the always-on `live-mutations` rule — this skill only classifies AWS-specific operations and lists tools.

## If the MCP server is not enabled

If `aws` MCP tools are not available, **stop and ask the user to enable the `aws` MCP server**. Do not fall back to Bash `aws`.

## Prefer goals over hardcoded API steps

Describe the outcome ("list untagged EC2 instances in this account") and let the agent pick tools. Prefer multi-step **read** work with the script tool over a long chain of one-shot calls.

| Tool family (names may vary by client prefix) | Use for |
|---|---|
| `call_aws` / `aws___call_aws` | Single authenticated AWS API/CLI-equivalent call (read **or** write) |
| `run_script` / `aws___run_script` | Multi-step logic in one sandboxed pass |
| `search_documentation` / `read_documentation` | Current AWS docs (not training-data recall) |
| `retrieve_skill` | Curated AWS procedures from the managed server |
| `list_regions` / `get_regional_availability` | Region and feature availability |
| `get_tasks` | Poll long-running tool tasks |
| `get_presigned_url` | Presigned URLs (sensitive; may enable write) |

## AWS-specific mutation classification

Follow `live-mutations` for authorization. Classify each underlying operation — `call_aws` / `run_script` are not inherently safe.

**Reads (use freely):** describe / list / get / head / filter / search / download-for-inspection — e.g. `sts get-caller-identity`, `ec2 describe-*`, `s3api list-*` / `head-*`, `iam get-*` / `list-*`, CloudWatch metrics/logs reads, docs tools, `list_regions`.

**Mutations (require explicit per-action authorization):** create / put / update / delete / terminate / stop / start / reboot; attach / detach / associate; tag / untag; IAM/KMS policy changes; S3 upload/delete/ACL; SG/NACL changes; ASG/RDS scaling; any `run_script` step that mutates; `get_presigned_url` when it enables write or long-lived privileged access.

Before mutating: propose exact action + resource IDs + region/account + blast radius; wait for yes on **that** proposal; prefer the smallest API surface.

## Auth and region

- Credentials: local AWS credential chain (`aws configure` / `aws login` / env / SSO). The proxy SigV4-signs to the managed endpoint.
- Default operation region in this config: **`us-east-1`** (`--metadata AWS_REGION=us-east-1`). Endpoint host region can differ from operation region if metadata changes later.
- Multi-account: proxy supports `--profile` — only change the MCP template when the user asks.

## Do not

- Fall back to Bash `aws` when the MCP server is simply disabled (ask to enable it)
- Use Context7 or Firecrawl for AWS service docs when this server's documentation tools are available
- Mutate because a write tool is listed, or shell out to `aws` / Terraform apply to bypass policy
