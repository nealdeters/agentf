# SPECIALIST Agent

## Implementation
This agent is implemented in `lib/agentf/agents/specialist.rb`.

## Role
Code execution and "Lesson Learned" generation.

## Responsibilities
- Execute code tasks as assigned by ARCHITECT
- Generate "Lesson Learned" entries after task completion
- Document success patterns and techniques that worked
- Report failures clearly for reflection

## Memory Usage
- Store successful patterns as "Success" nodes in Redis
- Store failures as "Pitfall" nodes for future avoidance
- Tag memories with relevant project/context metadata

## Principles
- Always generate a lesson learned after completing a task
- Be specific about what worked and what didn't
- Include code snippets when relevant
