# OpenClaw Integration Guide

OpenClaw is an AI agent orchestration platform that enables flexible, multi-model workflows with local execution.

## Key Features

- **Multi-Model Support**: Switch between OpenAI, Anthropic, Groq, Together AI, and more
- **Local Execution**: Run agents on your own infrastructure
- **Tool Integration**: Access filesystem, web search, cron jobs, and custom skills
- **Session Management**: Persistent state across conversations

## Quick Start

1. Install OpenClaw:
   ```bash
   npm install -g openclaw
   openclaw onboard
   ```

2. Configure providers in `~/.openclaw/openclaw.json`:
   ```json
   {
     "auth": {
       "profiles": {
         "openai:default": { "provider": "openai", "mode": "api_key" },
         "groq:default": { "provider": "groq", "mode": "api_key" }
       }
     },
     "models": {
       "providers": {
         "openai": { "baseUrl": "https://api.openai.com/v1" },
         "groq": { "baseUrl": "https://api.groq.com/openai/v1" }
       }
     }
   }
   ```

3. Switch models mid-session:
   ```
   /model groq-llama
   ```

## Useful Workflows

- **Cron Jobs**: Schedule automated tasks
- **GitHub Integration**: Manage repos, PRs, issues
- **Email Automation**: Monitor and send emails
- **Image Generation**: Batch generate with OpenAI
- **Web Research**: Search and fetch content

## Resources

- Official Docs: https://docs.openclaw.ai
- GitHub: https://github.com/openclaw/openclaw
- Community: https://discord.com/invite/clawd
