# Skills — Purpose

## Why This System Exists

Skills extend what the agent **knows how to do** without writing code. A skill is a markdown file (SKILL.md) that teaches the agent a new capability — like writing prose, generating diagrams, or interacting with a specific API — by providing instructions and context.

## The Problem It Solves

1. **Extensibility without code**: Users can add new agent capabilities by dropping a markdown file into a skills directory. No TypeScript, no plugin SDK, no compilation.

2. **Context budget management**: An agent can't have 150 skills all in its system prompt — that would consume the entire context window. The gating system filters skills by eligibility (OS, binaries, env vars) and the limits system caps the total prompt contribution.

3. **Safe environment injection**: Skills often need API keys (e.g., an OpenAI skill needs OPENAI_API_KEY). The env injection system safely provides these without allowing skills to overwrite dangerous system variables.

4. **Discovery and precedence**: Skills can come from the OpenClaw distribution, user workspace, personal agents directory, or plugins. A clear precedence order ensures workspace skills override bundled ones.

## What SwiftClaw Needs from This

The SKILL.md format (YAML frontmatter + markdown body) is the contract. SwiftClaw needs to parse this format, evaluate the gating rules (OS, bins, env, config), manage the prompt budget (count + character limits), and handle env var injection with the same safety guarantees.

## Key Insight for Replication

Skills are **prompt engineering as configuration**. Each skill is just text that gets injected into the agent's system prompt when eligible. The complexity is in the gating (deciding which skills to include) and budgeting (fitting them within token limits), not in the skills themselves.
