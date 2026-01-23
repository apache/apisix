---
title: AI Proxy with Anthropic Provider
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
  - Anthropic
  - Claude
  - LLM
description: This document provides a comprehensive guide on using the Anthropic provider within the ai-proxy plugin, detailing configuration, protocol translation, and usage examples.
---

## Overview

The \`ai-proxy\` plugin enables seamless integration with **Anthropic (Claude)** as a native provider. While many AI services offer OpenAI-compatible endpoints, Anthropic's Messages API maintains a distinct protocol structure. This plugin acts as a high-performance translation layer, allowing you to use standard OpenAI-style requests to interact with Claude models.

## Why Native Anthropic Support?

The primary challenge in proxying to Anthropic lies in the **System Prompt** handling:
- **OpenAI**: System instructions are embedded within the \`messages\` array.
- **Anthropic**: System instructions **must** be placed in a dedicated top-level \`system\` field.

APISIX automatically performs this "protocol surgery," ensuring your existing OpenAI-compatible applications can switch to Claude 3 without any code modifications.

## Provider Specifics: Anthropic

When \`provider\` is set to \`anthropic\`, the following transformations are applied:

### 1. Protocol Translation
- **System Message Extraction**: The plugin scans the \`messages\` array, extracts the content with the \`system\` role, and maps it to Anthropic's \`system\` field.
- **Role Mapping**: 
    - \`user\` -> \`user\`
    - \`assistant\` -> \`assistant\`
- **Response Conversion**: Anthropic's response (which uses a \`content\` array) is converted back to the OpenAI-compatible \`choices\` format, including token usage statistics.

### 2. Header Adaptation
- **Authentication**: Translates \`Authorization: Bearer <key>\` to \`x-api-key: <key>\`.
- **Version Control**: Automatically injects the \`anthropic-version: 2023-06-01\` header required by Anthropic.

### 3. Parameter Handling
- **max_tokens**: Anthropic requires this parameter. If not provided in the client request, the plugin defaults it to \`1024\`.

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
curl http://127.0.0.1:9080/v1/chat/completions -X POST \\
-H "Content-Type: application/json" \\
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
