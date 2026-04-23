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
    },
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen2.5-coder:7b": {
          "name": "Qwen2.5 Coder 7B"
        }
      }
    }
  },
  "instructions": []
}
