# Redis Memory Schema

## Overview
This document defines the memory node structures for the OpenCode Agentic Memory System using Redis Stack (Vector + JSON).

## Memory Types

### 1. Semantic Memory (Vector)
Used for "finding similar past tasks" via embedding similarity search.

**Index Name**: `semantic:tasks`

**Schema**:
- `id`: string (unique identifier)
- `content`: text (task description, for embedding)
- `embedding`: vector (1536 dims, cosine similarity)
- `project`: tag (project name)
- `language`: tag (programming language)
- `task_type`: tag (feature, bugfix, refactor, etc.)
- `success`: boolean (whether task succeeded)
- `created_at`: numeric (timestamp)
- `agent`: string (which agent created this)

### 2. Episodic Memory (JSON)
Used for storing specific success/failure logs with full context.

**Index Name**: `episodic:logs`

**Schema**:
- `$.id`: string (unique identifier)
- `$.type`: string (enum: "success", "pitfall", "lesson")
- `$.title`: string (brief summary)
- `$.description`: string (full details)
- `$.project`: string (project name)
- `$.context`: string (surrounding circumstances)
- `$.code_snippet`: string (relevant code, if any)
- `$.tags`: array of strings
-`: number (timestamp)
- `$.agent`: string (which `$.created_at agent created this)
- `$.related_task_id`: string (reference to semantic memory)

## Memory Operations

### Storing a Success
```python
{
    "id": "success_001",
    "type": "success",
    "title": "Used async/await for I/O operations",
    "description": "Found that using async/await significantly improved performance...",
    "project": "my-project",
    "context": "Processing multiple file uploads",
    "code_snippet": "async def process_files(files): ...",
    "tags": ["performance", "async", "python"],
    "created_at": 1706745600,
    "agent": "SPECIALIST",
    "related_task_id": "task_001"
}
```

### Storing a Pitfall
```python
{
    "id": "pitfall_001",
    "type": "pitfall",
    "title": "Forgot to close database connections",
    "description": "Connection pool exhaustion occurred after multiple requests...",
    "project": "my-project",
    "context": "Database operations in API handlers",
    "code_snippet": "# Bad: conn = get_connection()\n# Good: with get_connection() as conn:",
    "tags": ["database", "resource-leak", "python"],
    "created_at": 1706745600,
    "agent": "SPECIALIST",
    "related_task_id": "task_002"
}
```

### Storing a Lesson
```python
{
    "id": "lesson_001",
    "type": "lesson",
    "title": "Always validate input at API boundaries",
    "description": "Learned to use Pydantic models for request validation...",
    "project": "my-project",
    "context": "Building REST API endpoints",
    "code_snippet": "class UserRequest(BaseModel):\n    name: str\n    email: str",
    "tags": ["validation", "api", "pydantic"],
    "created_at": 1706745600,
    "agent": "SPECIALIST",
    "related_task_id": "task_003"
}
```

## Hybrid Search Strategy

1. **Initial Vector Search**: Query `semantic:tasks` index for top 5 similar tasks
2. **Filter by Metadata**: Apply project/language/tag filters
3. **Fetch Full Details**: Retrieve corresponding JSON from `episodic:logs`
4. **Rank and Return**: Combine scores, return top 3-5 relevant memories

## Key Principles

- **Avoid Context Bloat**: Limit retrieval to top 3-5 memories
- **Tag Everything**: Rich metadata enables better filtering
- **Reflect on Failures**: Always store pitfall nodes for failures
- **Include Code**: Code snippets make memories actionable
