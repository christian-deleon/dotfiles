---
name: aws-mcp
description: AWS API access via the `aws-api` MCP server. ALWAYS use whenever a task requires reading current AWS state (S3, EC2, IAM, Lambda, CloudFormation, CloudWatch, RDS, VPC, EKS, etc.) or when the user asks for AWS CLI commands or describes a state-of-the-cloud question — 'what's in this bucket', 'who has access to', 'what's the latest log', 'list my instances', 'show me the policy'. Routes all AWS API access through the MCP server, enforces read-only operations by default, and asks the user to enable the server if it is not available.
compatibility: opencode
---

# AWS MCP Usage

All AWS API access goes through the `aws-api` MCP server (`mcp__aws-api__*` tools). Do not shell out to the `aws` CLI via Bash for AWS API calls.

## If the MCP server is not enabled

If `mcp__aws-api__*` tools are not available, **stop and ask the user to enable the `aws-api` MCP server** before proceeding. Do not fall back to running `aws` via Bash, and do not try to construct API calls another way.

## Read-only by default

Only invoke read-only AWS actions (`Describe*`, `Get*`, `List*`, `Search*`, etc.).

Do not call any action that creates, modifies, or deletes AWS resources or configuration unless the user has **explicitly authorized that specific change in the current conversation**. A general "go ahead" is not enough — confirm the exact action and target resource before mutating.

When in doubt, treat the action as a mutation and ask first.
