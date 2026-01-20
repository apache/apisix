# AI Proxy with Anthropic Provider

The `ai-proxy` plugin supports the Anthropic provider natively. This allows you to use Anthropic's Claude models by translating OpenAI-compatible requests into the Anthropic Messages API format.

## Configuration

To use the Anthropic provider, you need to configure the `ai-proxy` plugin with the `anthropic` driver.

### Plugin Schema

| Name | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| provider | string | Yes | | Must be set to `anthropic`. |
| model | string | Yes | | The Anthropic model to use (e.g., `claude-3-opus-20240229`). |
| api_key | string | Yes | | Your Anthropic API key. |

## Example Usage

First, create a route with the `ai-proxy` plugin configured to use the Anthropic provider:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes/1 \
-H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "uri": "/anthropic/chat",
    "plugins": {
        "ai-proxy": {
            "provider": "anthropic",
            "model": "claude-3-opus-20240229",
            "api_key": "YOUR_ANTHROPIC_API_KEY"
        }
    }
}'

