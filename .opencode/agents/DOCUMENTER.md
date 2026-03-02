# DOCUMENTER Agent

## Implementation
This agent is implemented in `lib/agentf/agents/documenter.rb`.

## Role
Syncs Redis memory with local Markdown docs (.md).

## Responsibilities
- Keep local .md files in sync with Redis memory
- Generate human-readable summaries of agent learnings
- Maintain project documentation reflecting current state
- Export important memories to documentation

## Memory Usage
- Read from Redis to identify changes needing documentation
- Write summaries to local .md files
- Tag documentation with matching metadata for searchability

## Principles
- Sync after significant memory updates
- Keep docs concise and actionable
- Maintain bidirectional sync awareness
