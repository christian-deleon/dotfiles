{
  "$schema": "https://opencode.ai/config.json",
  "theme": "system",
  "autoupdate": false,
  "provider": {
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
    },
    "amazon-bedrock": {
      "options": {
        "region": "us-east-1"
      },
      "whitelist": [
        "deleon-grok-4.6",
        "deleon-claude-sonnet-5",
        "deleon-claude-opus-5"
      ],
      "models": {
        "deleon-grok-4.6": {
          "id": "arn:aws:bedrock:us-east-1:{env:BEDROCK_AWS_ACCOUNT_ID}:inference-profile/us.xai.grok-4.6",
          "name": "deleon-grok-4.6",
          "reasoning": true,
          "variants": {
            "low": {
              "reasoningConfig": {
                "type": "enabled",
                "maxReasoningEffort": "low"
              }
            },
            "medium": {
              "reasoningConfig": {
                "type": "enabled",
                "maxReasoningEffort": "medium"
              }
            },
            "high": {
              "reasoningConfig": {
                "type": "enabled",
                "maxReasoningEffort": "high"
              }
            },
            "xhigh": {
              "reasoningConfig": {
                "type": "enabled",
                "maxReasoningEffort": "xhigh"
              }
            }
          }
        },
        "deleon-claude-sonnet-5": {
          "id": "arn:aws:bedrock:us-east-1:{env:BEDROCK_AWS_ACCOUNT_ID}:inference-profile/us.anthropic.claude-sonnet-5",
          "name": "deleon-claude-sonnet-5"
        },
        "deleon-claude-opus-5": {
          "id": "arn:aws:bedrock:us-east-1:{env:BEDROCK_AWS_ACCOUNT_ID}:inference-profile/us.anthropic.claude-opus-5",
          "name": "deleon-claude-opus-5"
        }
      }
    },
    "amazon-bedrock-gov": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Amazon Bedrock (Gov)",
      "env": ["WORK_BEDROCK_API_KEY", "GROK_BEDROCK_API_KEY"],
      "options": {
        "baseURL": "https://bedrock-runtime.us-gov-west-1.amazonaws.com/openai/v1"
      },
      "models": {
        "work-grok-4.6": {
          "id": "us-gov.xai.grok-4.6",
          "name": "work-grok-4.6",
          "reasoning": true,
          "variants": {
            "low": {
              "reasoningEffort": "low"
            },
            "medium": {
              "reasoningEffort": "medium"
            },
            "high": {
              "reasoningEffort": "high"
            },
            "xhigh": {
              "reasoningEffort": "xhigh"
            }
          }
        }
      }
    }
  },
  "instructions": []
}
