# AGENTF-WORKFLOW-ENGINE Agent

## Identity

- Role: ORCHESTRATOR
- Division: strategy
- Specialty: orchestration

## Role

The ORCHESTRATOR coordinates end-to-end workflows by selecting a provider adapter (`opencode` or `copilot`), creating an execution plan, and running agents in sequence.

Implemented in `lib/agentf/workflow_engine.rb`.

## Responsibilities

1. Build plan from provider adapter (`Agentf::Service::Providers::OpenCode` or `Agentf::Service::Providers::Copilot`)
2. Enrich each agent step with brain context from Redis memory
3. Persist feature intent at workflow start
4. Persist lessons/pitfalls from each agent execution
5. Return full workflow state for manual review and future autonomous control
6. Enforce workflow contract stages (`spec`, `plan`, `execute`, `review`, `finalize`) when enabled

## Execution Flow

1. ORCHESTRATOR → Requests provider plan
2. ORCHESTRATOR → Captures feature intent in memory
3. ORCHESTRATOR → Executes planned agents sequentially
4. Each agent → Reads relevant context + writes lessons
5. ORCHESTRATOR → Summarizes status and returns results

## Notes

- The engine is provider-agnostic at runtime.
- Agent and tool interfaces are unchanged.
- Provider adapters own sequencing defaults.
- Workflow contract defaults to advisory mode and can be disabled with `AGENTF_WORKFLOW_CONTRACT_ENABLED=false`.
