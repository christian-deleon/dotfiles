---
name: aws-mcp
description: AWS API access via the `aws` MCP server (mcp-proxy-for-aws). Use for live AWS state (S3, EC2, IAM, Lambda, CloudWatch, RDS, EKS), current AWS docs, or account questions — 'what's in this bucket', 'who has access to X', 'list my instances'. Reads free; mutations need explicit per-action authorization.
compatibility: opencode
---

# AWS MCP Usage

All AWS API access goes through the **`aws`** MCP server (reached via `mcp-proxy-for-aws` → `https://aws-mcp.us-east-1.api.aws/mcp`). Do not shell out to the `aws` CLI via Bash for AWS API calls.

The proxy is **not** pinned `--read-only` — full tools (including write-capable `call_aws` / `run_script`) are available. **Availability is not permission.** Policy lives here and in the always-on `live-mutations` rule: read freely; mutate only with explicit per-action authorization in the current conversation.

## If the MCP server is not enabled

If `aws` MCP tools are not available, **stop and ask the user to enable the `aws` MCP server** before proceeding. Do not fall back to running `aws` via Bash, and do not try to construct API calls another way.

## Prefer goals over hardcoded API steps

Describe the outcome ("list untagged EC2 instances in this account") and let the agent pick tools. Prefer composing multi-step **read** work with the script tool rather than a long chain of one-shot API calls.

| Tool family (names may vary by client prefix) | Use for |
|---|---|
| `call_aws` / `aws___call_aws` | Single authenticated AWS API/CLI-equivalent call (read **or** write) |
| `run_script` / `aws___run_script` | Multi-step logic in one sandboxed pass (list → filter → optionally act) |
| `search_documentation` / `read_documentation` | Current AWS docs (not training-data recall) |
| `retrieve_skill` | Curated AWS procedures from the managed server |
| `list_regions` / `get_regional_availability` | Region and feature availability |
| `get_tasks` | Poll long-running tool tasks |
| `get_presigned_url` | Presigned URLs (treat as sensitive / potentially mutating side-effect) |

## Mutation posture (non-negotiable)

**Default is read-only.** The most common AI failure mode is treating "full MCP access" as license to create, delete, stop, or tag resources because the tools exist.

Do **not** call any mutating AWS action unless the user has **explicitly authorized that specific action on that specific resource (or clearly scoped set) in the current conversation**.

| Counts as authorized | Does **not** count |
|---|---|
| "Delete bucket `foo-logs` in us-east-1" | "fix it" / "go ahead" / "do whatever you need" |
| "Stop instance `i-0abc…`" after you named it | "clean up the sandbox" without naming targets |
| "Yes, run that `aws s3 rm …` you just proposed" | Implied permission from an earlier related task |
| A slash-command or skill the user invoked that states the mutation | Task success criteria that *could* be met by mutating |

When in doubt, treat the action as a mutation and **ask first**. Propose the exact CLI/API call (or script) and wait for a yes on that proposal.

### What is a read (use freely)

Describe / list / get / head / show / filter / search / download-for-inspection patterns that do not change account state. Examples:

- `sts get-caller-identity`, `ec2 describe-*`, `s3api list-*` / `head-*`, `iam get-*` / `list-*`
- CloudWatch `get-metric-data`, logs `filter-log-events` (read)
- Docs tools: `search_documentation`, `read_documentation`, `retrieve_skill`, `list_regions`

### What is a mutation (require explicit authorization)

Anything that creates, updates, deletes, or changes the runtime state of a resource — including "harmless" side effects:

- create / put / update / delete / terminate / stop / start / reboot
- attach / detach / associate / disassociate / enable / disable
- tag / untag (tags affect billing, IAM conditions, automation)
- IAM policy/role/user changes, KMS key policy changes
- S3 object upload, delete, ACL/policy changes; bucket config changes
- Security group rule changes, network ACL changes
- Starting/stopping instances, scaling ASGs, modifying RDS
- `run_script` that includes any of the above in any step
- `get_presigned_url` when it enables a write upload, or long-lived privileged access

`call_aws` and `run_script` are **not** themselves "safe" — classify each underlying operation. A multi-step script is a mutation if **any** step mutates.

### Before a mutation

1. State the exact action, resource identifiers, region/account, and blast radius in one short proposal.
2. Wait for explicit user confirmation of **that** proposal.
3. Execute only what was approved; if the plan changes mid-flight, re-ask.
4. Prefer the smallest API surface (one `call_aws` over a broad script) unless multi-step is clearly safer/clearer.

## Auth and region

- Credentials: local AWS credential chain (`aws configure` / `aws login` / env / SSO). The proxy SigV4-signs requests to the managed endpoint.
- Default operation region in this config: **`us-east-1`** (`--metadata AWS_REGION=us-east-1`). The endpoint host region (`us-east-1` in the URL) is where the MCP service runs; it can differ from the operation region if you later change metadata.
- Profile switching: proxy supports `--profile` if multi-account work needs it — only change the template when the user asks.

## Do not

- Fall back to Bash `aws` when the MCP server is simply disabled (ask the user to enable it)
- Use Context7 or Firecrawl for AWS service docs when this server's documentation tools are available
- Mutate because a write tool is listed or because the task *could* be fixed by mutating
- Bypass this policy by shelling out to `aws` / Terraform apply / console-equivalent CLIs for the same change
