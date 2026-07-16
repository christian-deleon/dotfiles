{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp", "--api-key", "op://ujvoilqaehz2gozzpp2jqyhxsu/g2vxfluvjcei5hfwmjbszlso44/credential"],
    "description": "Live documentation lookup"
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
    "command": "uvx",
    "args": [
      "mcp-proxy-for-aws@1.6.3",
      "https://aws-mcp.us-east-1.api.aws/mcp",
      "--metadata",
      "AWS_REGION=us-east-1",
      "--read-only"
    ],
    "description": "AWS API, docs, and skills (managed; read-only via proxy)"
  },
  "terraform": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "hashicorp/terraform-mcp-server:1.1.0"
    ],
    "description": "HashiCorp Terraform MCP (Registry + optional HCP/TFE)"
  },
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest", "--browser", "chrome", "--executable-path", "/usr/bin/chromium"],
    "description": "Browser automation and E2E testing"
  },
  "github": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-github"],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "op://ujvoilqaehz2gozzpp2jqyhxsu/lcpymvki7xwdbvucadxiy2ukpa/token"
    },
    "description": "GitHub operations - PRs, issues, repos"
  },
  "firecrawl": {
    "command": "npx",
    "args": ["-y", "firecrawl-mcp"],
    "env": {
      "FIRECRAWL_API_KEY": "op://ujvoilqaehz2gozzpp2jqyhxsu/qqxnvcu3mzmw6yosgtijqh3hv4/credential"
    },
    "description": "Web scraping and crawling"
  }
}
