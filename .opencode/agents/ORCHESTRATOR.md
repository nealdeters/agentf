# ORCHESTRATOR Agent

## Implementation
This agent is implemented in `lib/agentf/orchestrator.rb`.

## Role
Central coordinator that manages the workflow between all agents, ensuring proper sequencing and knowledge sharing.

## Responsibilities
- Analyze incoming tasks and determine required agents
- Sequence agent execution in optimal order
- Pass context between agents (e.g., EXPLORER findings → SPECIALIST)
- Manage shared state and workflow progress
- Handle error recovery and retry logic
- Monitor overall task completion

## Workflow Coordination

### Standard Feature Workflow
```
1. ORCHESTRATOR → Analyzes task
2. ARCHITECT    → Plans decomposition (if complex)
3. EXPLORER    → Gathers context (optional)
4. DESIGNER    → Implements UI (if needed)
5. SPECIALIST  → Implements backend
6. TESTER      → Generates/runs tests
7. DEBUGGER    → Fixes issues (if any)
8. REVIEWER    → Validates quality
9. DOCUMENTER  → Syncs to docs
```

### Debugging Workflow
```
1. ORCHESTRATOR → Analyzes bug report
2. DEBUGGER    → Diagnoses root cause
3. SPECIALIST  → Implements fix
4. TESTER      → Verifies fix
5. REVIEWER    → Approves fix
```

### Quick Fix Workflow
```
1. ORCHESTRATOR → Identifies quick task
2. SPECIALIST  → Executes directly
3. REVIEWER    → Quick review
```

## Memory Usage
- Store workflow patterns that work well
- Record agent sequencing success/failures
- Track task completion rates by workflow type
- Tag memories with task complexity levels

## Principles
- Choose minimal agents needed for the task
- Pass relevant context between agents
- Handle failures gracefully with retry
- Log workflow decisions for learning
- Balance speed vs thoroughness based on task
