{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp", "--api-key", "op://ujvoilqaehz2gozzpp2jqyhxsu/g2vxfluvjcei5hfwmjbszlso44/credential"],
    "description": "Live documentation lookup",
    "default": true
  },
  "grafana": {
    "command": "uvx",
    "args": ["mcp-grafana"],
    "env": {
      "GRAFANA_URL": "op://ujvoilqaehz2gozzpp2jqyhxsu/en2zsdbtnbi6rml6kpfklzdbva/url",
      "GRAFANA_SERVICE_ACCOUNT_TOKEN": "op://ujvoilqaehz2gozzpp2jqyhxsu/en2zsdbtnbi6rml6kpfklzdbva/credential"
    },
    "description": "Grafana dashboards and observability"
  },
  "docker": {
    "command": "uvx",
    "args": ["mcp-server-docker"],
    "description": "Docker container management"
  },
  "kubernetes": {
    "command": "npx",
    "args": ["-y", "kubernetes-mcp-server@latest"],
    "description": "Kubernetes cluster operations"
  },
  "flux": {
    "command": "flux-operator-mcp",
    "args": ["serve", "--read-only=false"],
    "env": {
      "KUBECONFIG": "$HOME/.kube/config"
    },
    "description": "Flux GitOps analysis, troubleshooting, and reconciliation"
  },
  "aws": {
    "command": "python3",
    "args": [
      "$HOME/.dotfiles/ai/scripts/aws_mcp_grok_shim.py",
      "uvx",
      "mcp-proxy-for-aws@1.6.4",
      "https://aws-mcp.us-east-1.api.aws/mcp",
      "--metadata",
      "AWS_REGION=us-east-1"
    ],
    "description": "AWS API, docs, and skills (managed; shim strips aws___ names for Grok)"
  },
  "playwright": {
    "command": "npx",
    "args": [
      "@playwright/mcp@latest",
      "--browser", "chrome",
      "--executable-path", "/usr/bin/chromium",
      "--user-data-dir", "$HOME/.config/chromium-agent",
      "--config", "$HOME/.dotfiles/ai/playwright-mcp.config.json",
      "--sandbox",
      "--output-dir", "/tmp/playwright-mcp",
      "--ignore-https-errors"
    ],
    "description": "Browser automation in a dedicated Chromium profile (runs alongside daily Chromium)"
  },
  "gitea": {
    "command": "gitea-mcp",
    "args": ["-t", "stdio"],
    "env": {
      "GITEA_HOST": "op://ujvoilqaehz2gozzpp2jqyhxsu/5u3m57x7mqfutefx7vlovda7zq/hostname",
      "GITEA_ACCESS_TOKEN": "op://ujvoilqaehz2gozzpp2jqyhxsu/5u3m57x7mqfutefx7vlovda7zq/credential"
    },
    "description": "Personal self-hosted Gitea (Netbird only; not for work)"
  },
  "firecrawl": {
    "command": "npx",
    "args": ["-y", "firecrawl-mcp"],
    "env": {
      "FIRECRAWL_API_KEY": "op://ujvoilqaehz2gozzpp2jqyhxsu/qqxnvcu3mzmw6yosgtijqh3hv4/credential"
    },
    "description": "Web scraping and crawling",
    "default": true
  }
}
