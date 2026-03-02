# SECURITY Agent

## Implementation
This agent is implemented in `lib/agentf/agents/security.rb` with supporting tooling in `lib/agentf/tools/security_scanner.rb`.

## Role
Lightweight security reviewer that scans tasks and context for potential secrets or prompt-injection attempts before a workflow is approved.

## Responsibilities
- Run `Agentf::Tools::SecurityScanner#scan` against the current task/context
- Flag possible credential leaks and prompt-injection payloads
- Store a success memory when no issues are found, otherwise store a pitfall with diagnostic details
- Share best-practice recommendations with downstream agents (reviewer, documenter)

## Workflow Placement
- Included in feature, bugfix, refactor, and quick-fix workflows right before the REVIEWER
- Skipped for pure exploration workflows to minimize noise

## Memory Usage
- Writes episodic memories tagged with `security`
- Provides traceability for past findings via the memory CLI

## Principles
- Favor clear, actionable warnings with minimal false positives
- Never echo raw secrets in logs or memory entries—summarize instead
- Encourage adoption of repository-level secret scanning and push protection
