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
  "time": {
    "command": "npx",
    "args": ["-y", "time-mcp"],
    "description": "Current time and timezone utilities"
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
  },
  "sequential-thinking": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"],
    "description": "Chain-of-thought reasoning"
  },
  "magic": {
    "command": "npx",
    "args": ["-y", "@magicuidesign/mcp@latest"],
    "description": "Magic UI components"
  },
  "filesystem": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem", "~/projects/"],
    "description": "Filesystem operations"
  },
  "cloudflare-docs": {
    "type": "http",
    "url": "https://docs.mcp.cloudflare.com/mcp",
    "description": "Cloudflare documentation search"
  }
}
