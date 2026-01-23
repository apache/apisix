---
title: AI Proxy with Anthropic Provider
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
  - Anthropic
  - Claude
description: This document explains how to use the Anthropic provider within the ai-proxy plugin, including configuration and protocol translation details.
---

## Description

The \`ai-proxy\` plugin now supports **Anthropic** as a native provider. This feature allows users to interact with Anthropic's Messages API using standard OpenAI-compatible request formats. APISIX handles the underlying protocol translation automatically.

## Provider Specifics: Anthropic

Anthropic's API has several structural differences compared to OpenAI. When the \`provider\` is set to \`anthropic\`, APISIX performs the following adaptations:

### 1. Protocol Translation
- **System Prompt**: OpenAI includes system instructions in the \`messages\` array. APISIX automatically extracts these and moves them to Anthropic's mandatory top-level \`system\` field.
- **Role Mapping**: Standardizes roles between OpenAI (user, assistant, system) and Anthropic's expected format.

### 2. Header Adaptation
- **Authentication**: Automatically converts the \`Authorization: Bearer <key>\` header into the \`x-api-key: <key>\` header required by Anthropic.
- **Version Header**: Automatically injects the \`anthropic-version\` header (default: \`2023-06-01\`).

### 3. Endpoint Routing
- Automatically routes requests to Anthropic's native endpoint: \`/v1/messages\`.

## Configuration

| Name | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| provider | string | Yes | | Must be set to \`anthropic\`. |
| model | string | Yes | | The Anthropic model to use (e.g., \`claude-3-5-sonnet-20240620\`). |
| api_key | string | Yes | | Your Anthropic API key. |

## Example

### Plugin Configuration

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

### Request Example

Users can send requests in the familiar OpenAI format:

\`\`\`bash
curl http://127.0.0.1:9080/v1/chat/completions -X POST \\
-H "Content-Type: application/json" \\
-d '{
    "model": "gpt-4",
    "messages": [
        {"role": "system", "content": "You are a helpful assistant"},
        {"role": "user", "content": "Hello, Claude!"}
    ]
}'
\`\`\`
