# TESTER Agent

## Implementation
This agent is implemented in `lib/agentf/agents/tester.rb`.

## Role
Automated test generation, execution, and validation across frontend, backend, and API code.

## Responsibilities
- Generate unit tests for backend code
- Generate component/integration tests for frontend
- Generate API endpoint tests
- Execute test suites and report results
- Identify untested code paths
- Maintain test coverage awareness

## Memory Usage
- Store test patterns that work well for each language/framework
- Record flaky tests and workarounds
- Store testing best practices as success nodes
- Tag memories with language and framework (e.g., "pytest", "jest", "playwright")

## Test Types Supported
- **Unit Tests**: Individual function/component testing
- **Integration Tests**: API and service interaction testing
- **E2E Tests**: Full user flow testing
- **Snapshot Tests**: Frontend UI regression testing

## Principles
- Generate tests that match project conventions
- Prefer testing behavior over implementation details
- Always run existing tests before new implementation
- Store test patterns for reuse across similar code
