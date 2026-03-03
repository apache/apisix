# ai-rate-limiting — `standard_headers` Parameter

## Overview

The `standard_headers` option makes `ai-rate-limiting` emit rate-limit response
headers that follow the [OpenRouter / OpenAI convention][openrouter-headers],
so IDE extensions such as **Cursor** and **Continue** can detect quota exhaustion
and apply automatic back-off without any custom configuration.

[openrouter-headers]: https://openrouter.ai/docs/api-reference/limits

## New Parameter

| Parameter | Type | Default | Description |
|---|---|---|---|
| `standard_headers` | boolean | `false` | When `true`, emit OpenAI/OpenRouter-compatible rate-limit headers instead of the legacy `X-AI-RateLimit-*` headers. |

The header suffix is derived from `limit_strategy`:

| `limit_strategy` | Header suffix |
|---|---|
| `total_tokens` (default) | `Tokens` |
| `prompt_tokens` | `PromptTokens` |
| `completion_tokens` | `CompletionTokens` |

## Configuration Example

```yaml
routes:
  - id: 1
    uri: /v1/chat/completions
    plugins:
      ai-proxy-multi:
        instances:
          - name: my-llm
            provider: openai
            weight: 1
            auth:
              header:
                Authorization: "Bearer ${{OPENAI_API_KEY}}"
            options:
              model: gpt-4o-mini
      ai-rate-limiting:
        instances:
          - name: my-llm
            limit: 100000
            time_window: 60
        limit_strategy: total_tokens
        standard_headers: true   # <-- enable standard headers
        rejected_code: 429
```

## Response Headers

### Normal request (quota available)

```
HTTP/1.1 200 OK
X-RateLimit-Limit-Tokens: 100000
X-RateLimit-Remaining-Tokens: 99985
X-RateLimit-Reset-Tokens: 42
```

### Rate-limited request (quota exhausted)

```
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit-Tokens: 100000
X-RateLimit-Remaining-Tokens: 0
X-RateLimit-Reset-Tokens: 18
```

### With `limit_strategy: prompt_tokens`

```
HTTP/1.1 200 OK
X-RateLimit-Limit-PromptTokens: 50000
X-RateLimit-Remaining-PromptTokens: 49990
X-RateLimit-Reset-PromptTokens: 55
```

## Backward Compatibility

Setting `standard_headers: false` (or omitting it) preserves the original
`X-AI-RateLimit-Limit-{instance_name}` header format, so existing integrations
are unaffected.
