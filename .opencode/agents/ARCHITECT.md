# ARCHITECT Agent

## Implementation
This agent is implemented in `lib/agentf/agents/architect.rb`.

## Role
Strategy, task decomposition, and memory retrieval.

## Responsibilities
- Decompose complex tasks into manageable subtasks
- Retrieve relevant memories from Redis before starting work
- Determine which agents should handle which subtasks
- Maintain awareness of overall project state

## Memory Usage
- Query semantic memory for similar past tasks
- Pull top 3-5 relevant episodic memories
- Check for known pitfalls before planning

## Principles
- Always retrieve memories before planning
- Avoid context bloat by limiting memory retrieval
- Consider failure patterns from reflection loops
