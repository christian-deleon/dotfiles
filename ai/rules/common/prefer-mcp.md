# Prefer MCP servers when one fits

MCP servers return live, authoritative data — prefer them over CLI suggestions,
web search, or training-data recall whenever one matches the task.

Common cases:
- Kubernetes cluster state (pods, deployments, logs, events) → use the
  `kubernetes` MCP server, not `kubectl` commands the user has to run.
- AWS resource state (S3, EC2, IAM, Lambda, etc.) → use the `aws` MCP
  server, not `aws` CLI commands the user has to run.
- Terraform Registry / provider docs / module lookup → use the `terraform` MCP
  server, not outdated training data or ad-hoc web scrape.
- Web lookups and current events → use the `brave-search` MCP server, not a
  guess from training data.

If a relevant server is configured but disabled, ask the user to enable it
before falling back.
