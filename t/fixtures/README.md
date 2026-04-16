# AI Gateway Test Fixtures

This directory contains mock API responses used by AI proxy test cases.
Instead of duplicating response data in each `.t` file, tests reference
fixture files via the `X-AI-Fixture` request header.

## Directory Structure

```
fixtures/
├── openai/                 # Standard OpenAI API responses
├── anthropic/              # Anthropic Messages API responses
├── protocol-conversion/    # Provider-specific SSE edge cases for protocol conversion
├── vertex-ai/              # Google Vertex AI responses
├── aliyun/                 # Aliyun content moderation responses
├── prometheus/             # Minimal responses for metrics tests
└── README.md               # This file
```

## File Formats

### JSON fixtures (`.json`)

Complete JSON response bodies, exactly as returned by the provider.
Supports `{{model}}` template — replaced at serve time with the model
from the request body.

### SSE fixtures (`.sse`)

Raw Server-Sent Events text with preserved event types and ordering.
Served with `Content-Type: text/event-stream`.

## Using Fixtures in Tests

Tests point the upstream at the built-in test server (port 1980) and specify
which fixture to serve via the `X-AI-Fixture` header:

```perl
=== TEST: Chat with OpenAI fixture
--- request
POST /v1/chat/completions
{"model":"test","messages":[{"role":"user","content":"hello"}]}
--- more_headers
X-AI-Fixture: openai/chat-basic.json
--- response_body_like
"content":"Hello! How can I help you?"
```

### Custom Status Codes

Use `X-AI-Fixture-Status` to override the HTTP status code:

```perl
--- more_headers
X-AI-Fixture: openai/chat-basic.json
X-AI-Fixture-Status: 429
--- error_code: 429
```

### Model Template

Fixtures containing `{{model}}` have it replaced with the model from the
request body at serve time. Used by rate-limiting tests to verify model
passthrough.

## Adding New Fixtures

1. Create the fixture file in the appropriate subdirectory
2. Use the exact response format from the provider (no wrapping or metadata)
3. For SSE files, end with `data: [DONE]\n\n` (OpenAI) or `event: message_stop\n` (Anthropic)
4. Reference it in your test with `X-AI-Fixture: <path-relative-to-fixtures/>`
