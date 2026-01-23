---
title: AI Proxy with Anthropic Provider
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
  - Anthropic
  - Claude
description: Detailed guide for using the native Anthropic provider in the ai-proxy plugin.
---

## Description

The \`ai-proxy\` plugin provides native support for **Anthropic (Claude)**. This allows users to use OpenAI-compatible requests while APISIX handles the protocol translation to Anthropic's Messages API.

## Key Features

- **System Prompt Mapping**: Automatically extracts system messages to Anthropic's top-level \`system\` field.
- **Header Adaptation**: Converts \`Authorization\` to \`x-api-key\` and injects \`anthropic-version\`.
- **Response Formatting**: Converts Anthropic's response back to OpenAI-compatible JSON.

## Configuration

| Name | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| provider | string | Yes | | Must be set to \`anthropic\`. |
| model | string | Yes | | The Anthropic model ID (e.g., \`claude-3-5-sonnet-20240620\`). |
| api_key | string | Yes | | Your Anthropic API key. |
| override.endpoint | string | No | \`https://api.anthropic.com/v1/messages\` | Custom endpoint for the provider. |

## Usage Examples

### Basic Configuration

\`\`\`json
{
    "plugins": {
        "ai-proxy": {
            "provider": "anthropic",
            "model": "claude-3-5-sonnet-20240620",
            "api_key": "your-anthropic-api-key"
        }
    }
}
\`\`\`

### Multi-turn Conversation Request

You can send a standard OpenAI-style multi-turn request:

\`\`\`bash
curl http://127.0.0.1:9080/v1/chat/completions -X POST \
-H "Content-Type: application/json" \
-d '{
    "model": "gpt-4",
    "messages": [
        {"role": "system", "content": "You are a professional translator."},
        {"role": "user", "content": "Translate the following to French: Hello, how are you?"}
    ],
    "max_tokens": 500
}'
\`\`\`

APISIX will transform this into the Anthropic-native format and return a standardized OpenAI-compatible response.
