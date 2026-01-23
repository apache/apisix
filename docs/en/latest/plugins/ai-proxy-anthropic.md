---
title: AI Proxy with Anthropic Provider
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
  - Anthropic
  - Claude
description: This document explains how to use the Anthropic provider within the ai-proxy plugin.
---

## Description

The \`ai-proxy\` plugin now supports **Anthropic** as a native provider. This feature allows users to interact with Anthropic's Messages API using standard OpenAI-compatible request formats.

## Provider Specifics: Anthropic

### 1. Protocol Translation
- **System Prompt**: Automatically moves system messages to Anthropic's top-level \`system\` field.
- **Role Mapping**: Standardizes roles between OpenAI and Anthropic.

### 2. Header Adaptation
- **Authentication**: Converts \`Authorization: Bearer\` to \`x-api-key\`.
- **Version Header**: Injects \`anthropic-version: 2023-06-01\`.

## Example

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
