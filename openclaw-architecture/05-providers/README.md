# 05 — LLM Providers

The provider system connects OpenClaw to large language models. It abstracts away the differences between OpenAI, Anthropic, Google, and 17+ other providers behind a single interface.

## The Provider Interface

Every provider is configured with:

```
ModelProviderConfig:
  baseUrl: string          # API endpoint (e.g., "https://api.anthropic.com/v1")
  apiKey: SecretInput      # API key (supports env refs, file refs, exec refs)
  auth: string             # Auth mode: "api-key" | "aws-sdk" | "oauth" | "token"
  api: string              # Protocol: "openai-completions" | "anthropic-messages" | etc.
  headers: Record          # Custom HTTP headers
  models: ModelDefinition[]  # Available models
```

### API Protocols

Different providers use different API protocols:

| Protocol | Providers |
|----------|-----------|
| `openai-completions` | OpenAI, OpenRouter, HuggingFace, vLLM, Vercel AI, Cloudflare AI, Together AI, Venice AI, NVIDIA, Moonshot, Kilocode |
| `anthropic-messages` | Anthropic (Claude) |
| `google-generative-ai` | Google (Gemini) |
| `bedrock-converse-stream` | Amazon Bedrock |
| `ollama` | Ollama (local) |
| `github-copilot` | GitHub Copilot |

### Model Definition

Each model has these properties:

```
ModelDefinitionConfig:
  id: string              # Model identifier (e.g., "claude-opus-4-6")
  name: string            # Display name
  api: string             # Protocol override (if different from provider)
  reasoning: boolean      # Supports extended thinking
  input: ["text", "image"]  # Input modalities
  cost:
    input: number         # Cost per 1M input tokens
    output: number        # Cost per 1M output tokens
    cacheRead: number     # Cost per 1M cache read tokens
    cacheWrite: number    # Cost per 1M cache write tokens
  contextWindow: number   # Max context size in tokens
  maxTokens: number       # Max output tokens
  headers: Record         # Model-specific HTTP headers
  compat:                 # Provider-specific capabilities
    supportsStore: boolean
    supportsDeveloperRole: boolean
    supportsReasoningEffort: boolean
    supportsUsageInStreaming: boolean
    supportsTools: boolean
    supportsStrictMode: boolean
    maxTokensField: string   # "max_completion_tokens" vs "max_tokens"
    thinkingFormat: string   # "openai" | "zai" | "qwen"
```

## All 20+ Providers

### Tier 1: First-Class Providers

| Provider | Key | API | Models |
|----------|-----|-----|--------|
| **Anthropic** | `anthropic` | anthropic-messages | Claude family |
| **OpenAI** | `openai` | openai-completions | GPT-4, GPT-4o, o1, o3 |
| **Google** | `google` | google-generative-ai | Gemini family |
| **Ollama** | `ollama` | ollama | Any local model |

### Tier 2: Cloud Providers

| Provider | Key | API | Notes |
|----------|-----|-----|-------|
| **OpenRouter** | `openrouter` | openai-completions | Multi-provider proxy |
| **Amazon Bedrock** | `amazon-bedrock` | bedrock-converse-stream | AWS credentials |
| **GitHub Copilot** | `github-copilot` | github-copilot | GitHub token exchange |
| **HuggingFace** | `huggingface` | openai-completions | Inference endpoints |
| **Together AI** | `together` | openai-completions | Various open models |
| **NVIDIA** | `nvidia` | openai-completions | NVIDIA models |

### Tier 3: Regional/Specialized

| Provider | Key | API | Notes |
|----------|-----|-----|-------|
| **Volcano Engine** | `volcengine` | openai-completions | Bytedance (China) |
| **BytePlus** | `byteplus` | openai-completions | Bytedance (global) |
| **Qianfan** | `qianfan` | openai-completions | Baidu (China) |
| **Minimax** | `minimax` | openai-completions | Chinese AI |
| **Moonshot/Kimi** | `moonshot` | openai-completions | Chinese AI |
| **Kilocode** | `kilocode` | openai-completions | Alibaba gateway |
| **Venice AI** | `venice` | openai-completions | Privacy-focused |
| **Vercel AI Gateway** | `vercel-ai-gateway` | openai-completions | Vercel proxy |
| **Cloudflare AI** | `cloudflare-ai-gateway` | openai-completions | Cloudflare proxy |
| **vLLM** | `vllm` | openai-completions | Self-hosted inference |

## SSE Streaming

All providers use **Server-Sent Events (SSE)** for streaming responses. Here's how it works:

### The Pattern

1. OpenClaw sends a POST request to the provider's API with `stream: true`
2. The provider responds with `Content-Type: text/event-stream`
3. Each chunk arrives as a line prefixed with `data: `
4. The stream ends with `data: [DONE]`

### Example SSE Stream

```
data: {"id":"msg_01","type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}

data: {"id":"msg_01","type":"content_block_delta","delta":{"type":"text_delta","text":", how"}}

data: {"id":"msg_01","type":"content_block_delta","delta":{"type":"text_delta","text":" can I help?"}}

data: {"id":"msg_01","type":"message_stop","usage":{"input_tokens":50,"output_tokens":12}}

data: [DONE]
```

### Implementation Flow

1. **Event subscription**: OpenClaw subscribes to the agent event stream
2. **Role chunk**: Send initial `{ delta: { role: "assistant" } }`
3. **Content chunks**: Stream text incrementally as it arrives
4. **Lifecycle events**: Wait for "end" or "error"
5. **Done marker**: Send `[DONE]`
6. **Cleanup**: Unsubscribe and close

### Error Recovery

- If streaming stalls, send buffered content when lifecycle completes
- If the connection drops, unsubscribe immediately
- On error, send error chunk with `finish_reason: "stop"`

## Auth Profile System

OpenClaw can manage **multiple API keys** per provider and rotate between them.

### Why Multiple Keys?

- Rate limits: When one key hits a limit, switch to another
- Cost splitting: Spread usage across billing accounts
- Redundancy: If one key is revoked, others still work

### Profile Types

```
ApiKeyCredential:  { apiKey: "sk-..." }
OAuthCredential:   { oauthToken: "...", refreshToken: "...", expiresAt: ... }
TokenCredential:   { token: "..." }
```

### Failure Tracking

Each profile tracks its health:

```
ProfileUsageStats:
  lastUsed: timestamp
  cooldownUntil: timestamp        # Transient cooldown expiry
  disabledUntil: timestamp        # Permanent disable expiry
  disabledReason: string          # "auth" | "billing" | "rate_limit" | etc.
  errorCount: number              # Rolling error counter
  failureCounts: { reason: count }
  lastFailureAt: timestamp
```

### Cooldown Calculation

| Failure Type | Cooldown Duration | Recoverable? |
|-------------|-------------------|--------------|
| Rate limit (429) | 60 seconds | Yes |
| Overloaded (503) | 10 seconds | Yes |
| Timeout (408) | 5 seconds | Yes |
| Auth failure (401) | Until user fixes | No |
| Billing (402) | Until user fixes | No |
| Quota exceeded | Until user fixes | No |
| Unknown | 5 minutes | Maybe |

### Profile Selection

When making an API call, profiles are selected in this order:
1. Explicit match from session config
2. Ordered list from `auth.order` config
3. Most recently used (round-robin effect)
4. Last known good
5. First available

Profiles in cooldown are skipped automatically.

## Model Failover

When the primary model fails, OpenClaw tries fallbacks:

### Model Reference Format

Models are referenced as `provider/model`:
- `"anthropic/claude-opus-4-6"`
- `"openai/gpt-4o"`
- `"ollama/llama3"`

### Aliasing

Human-readable aliases can be configured:
- `"my-claude"` → `"anthropic/claude-opus-4-6"`
- `"opus-4.6"` → `"claude-opus-4-6"` (auto-normalized)
- `"gemini-3-pro"` → `"gemini-3-pro-preview"` (auto-normalized)

### Resolution Order

1. Check agent-specific model override
2. Check global default model
3. Validate against configured model allowlist
4. Fall back to first available model
5. Hard default: `"anthropic/claude-opus-4-6"`

## Provider Discovery

Some providers support **automatic model discovery**:

| Provider | Discovery Method |
|----------|-----------------|
| Ollama | Calls `/api/tags` to list installed models |
| vLLM | Calls `/models` endpoint |
| Amazon Bedrock | AWS API to list available models |
| HuggingFace | Enumerate deployed inference endpoints |

## Token Counting & Cost Tracking

OpenClaw tracks token usage and costs per session:

```
SessionCostSummary:
  inputTokens: number
  outputTokens: number
  cacheReadTokens: number
  cacheWriteTokens: number
  totalTokens: number
  totalCost: number           # In USD
  dailyBreakdown: [...]       # Per-day usage
  dailyModelUsage: [...]      # Per-model per-day
  messageCounts: { user, assistant, tool }
  toolUsage: { toolName: count }
  modelUsage: [{ model, tokens, cost }]
```

Each provider has its own cost rates per model. OpenClaw uses these rates plus actual token counts from API responses to calculate costs.

## Secret Input Types

API keys can come from multiple sources:

```
# Plaintext (not recommended)
"apiKey": "sk-ant-api03-..."

# Environment variable (recommended)
"apiKey": { "env": "ANTHROPIC_API_KEY" }

# File (for Kubernetes/Docker secrets)
"apiKey": { "file": "/run/secrets/anthropic.key" }

# Executable (for dynamic credentials like AWS SSO)
"apiKey": { "exec": "aws sso login --profile my-profile" }
```

Secret references are resolved lazily — only when needed.

## Configuration Example

```json
{
  "models": {
    "providers": {
      "anthropic": {
        "baseUrl": "https://api.anthropic.com/v1",
        "apiKey": { "env": "ANTHROPIC_API_KEY" },
        "models": [
          {
            "id": "claude-opus-4-6",
            "name": "Claude Opus 4.6",
            "reasoning": true,
            "input": ["text", "image"],
            "cost": { "input": 0.015, "output": 0.075, "cacheRead": 0.0015, "cacheWrite": 0.02 },
            "contextWindow": 200000,
            "maxTokens": 16000
          }
        ]
      },
      "ollama": {
        "baseUrl": "http://localhost:11434"
      }
    }
  }
}
```

## Key Implementation Files

| File | Purpose | Size |
|------|---------|------|
| `models-config.providers.ts` | Master provider registry | 1,111 lines |
| `openai-http.ts` | OpenAI-compatible SSE streaming | 612 lines |
| `openresponses-http.ts` | OpenAI Responses API streaming | 450+ lines |
| `model-selection.ts` | Model resolution and aliasing | 410+ lines |
| `auth-profiles/types.ts` | Auth profile type definitions | — |
| `auth-profiles/order.ts` | Profile selection order | — |
| `auth-profiles/usage.ts` | Cooldown and usage tracking | — |

## Swift Replication Notes

1. **Provider protocol**: Define `LLMProvider` with async streaming (already exists in SwiftClaw as `ProviderKit`)
2. **SSE parsing**: Use URLSession's `AsyncBytes` to parse `data:` lines
3. **Auth profiles**: Codable struct with cooldown tracking
4. **Secret resolution**: Support env vars, files, and process execution
5. **Model registry**: Static registry for built-in providers, dynamic for Ollama/vLLM
6. **Cost tracking**: Per-session accumulator with model-specific rates
