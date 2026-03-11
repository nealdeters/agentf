# Redis Memory Schema

## Overview
This document defines the memory node structures for Agentf using Redis Stack (RedisJSON + RediSearch).

## Memory Types

### 1. Semantic Memory (`semantic:*`)
Used for finding similar past tasks by embedding similarity.

**Schema**:
- `id`: string
- `content`: text
- `embedding`: vector payload
- `project`: tag
- `language`: tag
- `task_type`: tag
- `success`: boolean
- `created_at`: numeric timestamp
- `agent`: string

### 2. Episodic Memory (`episodic:*`)
Used for success, pitfall, lesson, and intent records.

**Search index**: `episodic:logs`

**Schema fields**:
- `$.id`
- `$.type`
- `$.title`
- `$.description`
- `$.project`
- `$.context`
- `$.code_snippet`
- `$.tags`
- `$.created_at`
- `$.agent`
- `$.related_task_id`
- `$.metadata.intent_kind`
- `$.metadata.priority`

## Memory Commands

- Read recent: `agentf memory recent -n 10`
- Search: `agentf memory search "query" -n 10`
- Add lesson: `agentf memory add-lesson "<title>" "<description>" --agent=<AGENT>`
- Add success: `agentf memory add-success "<title>" "<description>" --agent=<AGENT>`
- Add pitfall: `agentf memory add-pitfall "<title>" "<description>" --agent=<AGENT>`
