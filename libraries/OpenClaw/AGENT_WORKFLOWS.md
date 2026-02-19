# Agent Workflows for OpenClaw

Once OpenClaw is running, here's what you can actually DO with it.

## Model Switching

Agents aren't locked to one model. Switch mid-session for different tasks:

```bash
# Fast/cheap tasks - Groq
/model groq-llama

# Reasoning-heavy work - Kimi K2.5
/model together/moonshotai/Kimi-K2.5

# Auto-routing - OpenRouter picks best backend
/model OpenRouter
```

## Automation Patterns

### 1. Cron Jobs \n
Sceedule recurring tasks with iso....