{
  "$schema": "https://opencode.ai/config.json",
  "theme": "system",
  "autoupdate": false,
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["npx", "-y", "@upstash/context7-mcp", "--api-key", "op://ujvoilqaehz2gozzpp2jqyhxsu/g2vxfluvjcei5hfwmjbszlso44/credential"]
    },
    "grafana": {
      "type": "local",
      "command": ["/home/cdeleon/.local/share/mise/shims/uvx", "mcp-grafana"],
      "environment": {
        "GRAFANA_URL": "https://grafana.athenis.io",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "op://ct4j6x7pd22bppwmdzx73gyfna/fu2r7xspuv22dgqst5yk7aaucu/credential"
      }
    },
    "time": {
      "type": "local",
      "command": ["npx", "-y", "time-mcp"]
    },
    "docker": {
      "type": "local",
      "command": ["/home/cdeleon/.local/share/mise/shims/uvx", "mcp-server-docker"]
    },
    "kubernetes": {
      "type": "local",
      "command": ["npx", "-y", "kubernetes-mcp-server@latest"]
    },
    "playwright": {
      "type": "local",
      "command": ["npx", "@playwright/mcp@latest", "--browser", "chrome", "--executable-path", "/usr/bin/chromium"]
    },
    "brave-search": {
      "type": "local",
      "command": ["npx", "-y", "@brave/brave-search-mcp-server"],
      "environment": {
        "BRAVE_API_KEY": "op://ujvoilqaehz2gozzpp2jqyhxsu/foc5j53cmytedcdwf25vnyt4t4/credential"
      }
    }
  }
}
