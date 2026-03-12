{
  "$schema": "https://opencode.ai/config.json",
  "_plugin_todo": "TEMPORARY: remove 'opencode-anthropic-context-1m' once OpenCode sends context-1m-2025-08-07 beta header natively. Track: https://github.com/anomalyco/opencode/issues/13455",
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
  },
  "instructions": [
    "/home/cdeleon/.dotfiles/ecc/.opencode/instructions/INSTRUCTIONS.md"
  ]
}
