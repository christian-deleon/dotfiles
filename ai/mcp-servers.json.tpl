{
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp", "--api-key", "op://ujvoilqaehz2gozzpp2jqyhxsu/g2vxfluvjcei5hfwmjbszlso44/credential"],
    "description": "Live documentation lookup"
  },
  "grafana": {
    "command": "/home/cdeleon/.local/share/mise/shims/uvx",
    "args": ["mcp-grafana"],
    "env": {
      "GRAFANA_URL": "https://grafana.athenis.io",
      "GRAFANA_SERVICE_ACCOUNT_TOKEN": "op://ct4j6x7pd22bppwmdzx73gyfna/fu2r7xspuv22dgqst5yk7aaucu/credential"
    },
    "description": "Grafana dashboards and observability"
  },
  "docker": {
    "command": "/home/cdeleon/.local/share/mise/shims/uvx",
    "args": ["mcp-server-docker"],
    "description": "Docker container management"
  },
  "kubernetes": {
    "command": "npx",
    "args": ["-y", "kubernetes-mcp-server@latest"],
    "description": "Kubernetes cluster operations"
  },
  "aws-api": {
    "command": "uvx",
    "args": ["awslabs.aws-api-mcp-server@latest"],
    "env": {
      "READ_OPERATIONS_ONLY": "true",
      "REQUIRE_MUTATION_CONSENT": "true"
    },
    "description": "AWS API access (awslabs official, read-only by default)"
  },
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest", "--browser", "chrome", "--executable-path", "/usr/bin/chromium"],
    "description": "Browser automation and E2E testing"
  },
  "brave-search": {
    "command": "npx",
    "args": ["-y", "@brave/brave-search-mcp-server"],
    "env": {
      "BRAVE_API_KEY": "op://ujvoilqaehz2gozzpp2jqyhxsu/foc5j53cmytedcdwf25vnyt4t4/credential"
    },
    "description": "Web search via Brave"
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
  },
  "memory": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-memory"],
    "description": "Persistent memory across sessions"
  }
}
