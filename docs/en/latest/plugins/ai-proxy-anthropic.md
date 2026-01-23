---
title: AI Proxy with Anthropic Provider
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
  - Anthropic
  - Claude
description: This document provides a comprehensive guide on using the Anthropic provider within the ai-proxy plugin, detailing configuration, protocol translation, and usage examples.
---

## Description

The \`ai-proxy\` plugin enables seamless integration with **Anthropic (Claude)** as a native provider. While many AI services offer OpenAI-compatible endpoints, Anthropic's Messages API maintains a distinct protocol structure. This plugin acts as a high-performance translation layer, allowing you to use standard OpenAI-style requests to interact with Claude models.

## Attributes

When the \`provider\` is set to \`anthropic\`, the following attributes are used to configure the connection:

| Name | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| provider | string | Yes | | Must be set to \`anthropic\`. |
| model | string | Yes | | The Anthropic model ID (e.g., \`claude-3-5-sonnet-20240620\`). |
| api_key | string | Yes | | Your Anthropic API key for authentication. |
| override.endpoint | string | No | \`https://api.anthropic.com/v1/messages\` | Custom endpoint for the Anthropic provider. |

## How To Use

APISIX automatically performs "protocol translation" when using the Anthropic provider. This ensures that your existing OpenAI-compatible applications can switch to Claude models without any code modifications.

### Protocol Translation Details

1. **System Prompt Handling**: OpenAI embeds system instructions within the \`messages\` array. APISIX automatically extracts these and maps them to Anthropic's mandatory top-level \`system\` field.
2. **Header Adaptation**:
   - Translates \`Authorization: Bearer <key>\` to \`x-api-key: <key>\`.
   - Automatically injects the \`anthropic-version: 2023-06-01\` header.
3. **Response Conversion**: Anthropic's response format is converted back to the OpenAI-compatible structure, including token usage statistics.

## Example

### Basic Configuration

The following example shows how to configure the \`ai-proxy\` plugin with the Anthropic provider on a specific route:

\`\`\`json
{
    "uri": "/v1/chat/completions",
    "plugins": {
        "ai-proxy": {
            "provider": "anthropic",
            "model": "claude-3-5-sonnet-20240620",
            "api_key": "your-anthropic-api-key"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "api.anthropic.com:443": 1
        },
        "pass_host": "host",
        "scheme": "https"
    }
}
\`\`\`

### Request Example

Once configured, you can send a standard OpenAI-style request:

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
