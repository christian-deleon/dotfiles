{
  "$schema": "https://opencode.ai/config.json",
  "theme": "system",
  "autoupdate": false,
  "model": "anthropic/claude-sonnet-4-6",
  "provider": {
    "anthropic": {
      "models": {
        "claude-sonnet-4-5": {
          "limit": {
            "context": 1024000,
            "output": 64000
          }
        },
        "claude-sonnet-4-5-20250929": {
          "limit": {
            "context": 1024000,
            "output": 64000
          }
        },
        "claude-sonnet-4-6": {
          "limit": {
            "context": 1024000,
            "output": 64000
          }
        }
      }
    }
  }
}
