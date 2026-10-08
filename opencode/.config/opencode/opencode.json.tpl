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
        "deleon-grok-4.7",
        "deleon-claude-sonnet-5.5",
        "deleon-claude-opus-5.5"
      ],
      "models": {
        "deleon-grok-4.7": {
          "id": "arn:aws:bedrock:us-east-1:{env:BEDROCK_AWS_ACCOUNT_ID}:inference-profile/us.xai.grok-4.7",
          "name": "deleon-grok-4.7",
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
        "deleon-claude-sonnet-5.5": {
          "id": "arn:aws:bedrock:us-east-1:{env:BEDROCK_AWS_ACCOUNT_ID}:inference-profile/global.anthropic.claude-sonnet-5-5",
          "name": "deleon-claude-sonnet-5.5",
          "reasoning": false,
          "variants": {
            "low": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "low"
                }
              }
            },
            "medium": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "medium"
                }
              }
            },
            "high": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "high"
                }
              }
            },
            "xhigh": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "xhigh"
                }
              }
            },
            "max": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "max"
                }
              }
            }
          }
        },
        "deleon-claude-opus-5.5": {
          "id": "arn:aws:bedrock:us-east-1:{env:BEDROCK_AWS_ACCOUNT_ID}:inference-profile/us.anthropic.claude-opus-5-5",
          "name": "deleon-claude-opus-5.5",
          "reasoning": false,
          "variants": {
            "low": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "low"
                }
              }
            },
            "medium": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "medium"
                }
              }
            },
            "high": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "high"
                }
              }
            },
            "xhigh": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "xhigh"
                }
              }
            },
            "max": {
              "additionalModelRequestFields": {
                "thinking": {
                  "type": "adaptive",
                  "display": "summarized"
                },
                "output_config": {
                  "effort": "max"
                }
              }
            }
          }
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
    },
    "genai-mil": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "GenAI.mil",
      "env": ["GENAI_MIL_API_KEY"],
      "options": {
        "baseURL": "https://api.genai.mil/v1"
      },
      "models": {
        "gemini-2.5-pro": {
          "name": "Gemini 2.5 Pro"
        },
        "gemini-3.1-pro-preview": {
          "name": "Gemini 3.1 Pro Preview"
        },
        "gemini-3.5-flash": {
          "name": "Gemini 3.5 Flash"
        },
        "gemini-3.7-flash": {
          "name": "Gemini 3.7 Flash"
        },
        "gemini-3.8-flash": {
          "name": "Gemini 3.8 Flash"
        }
      }
    }
  },
  "instructions": []
}
