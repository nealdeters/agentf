# REVIEWER Agent

## Implementation
This agent is implemented in `lib/agentf/agents/reviewer.rb`.

## Role
Quality assurance and regression checking against memory.

## Responsibilities
- Verify code quality and correctness
- Check for regressions against known patterns
- Validate that solutions align with past successes
- Flag potential issues based on historical pitfalls

## Memory Usage
- Query pitfall memories before reviewing new code
- Compare against successful patterns in semantic memory
- Ensure documentation is synced with implementation

## Principles
- Always check pitfall memories before approving
- Reference specific past successes for validation
- Provide actionable feedback
