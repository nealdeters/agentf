# Security Practices for Agentf

Agentf includes a dedicated **SECURITY** agent that runs in every workflow (aside from pure exploration) to surface potential risks early. The agent leverages `Agentf::Tools::SecurityScanner`, which performs lightweight detection for:

- Hard-coded secrets (API keys, private keys, password assignments)
- Prompt-injection attempts that try to exfiltrate environment variables or override instructions

While this provides a safety net, you should pair it with additional "shift-left" security measures:

1. **Pre-commit secret scanning**
   - Install tools such as [Gitleaks](https://github.com/gitleaks/gitleaks) or [TruffleHog](https://github.com/trufflesecurity/trufflehog)
   - Wire them into Git hooks (e.g., via [pre-commit](https://pre-commit.com/)) so sensitive strings are blocked before a push. A starter `.pre-commit-config.yaml` with a Gitleaks hook ships with this repository. Install pre-commit with `brew install pre-commit` (or `pipx install pre-commit`) and then run `pre-commit install`.

2. **Push protection**
   - Enable GitHub's Secret Scanning Push Protection under repository settings to block commits containing known secret patterns

3. **Log sanitisation**
   - Ensure verbose agent logs strip response headers/bodies to avoid storing API keys returned from upstream providers

4. **Memory hygiene**
   - Avoid saving raw secrets in Redis episodic memory; use references, masked values, or encrypted blobs instead

5. **Prompt hardening**
   - Update system prompts to reject "print env" or "ignore previous instructions" payloads, and restrict the agent's toolset from accessing sensitive shell commands

6. **Continuous review**
   - Periodically review the output of the SECURITY agent's stored memories (via `agentf memory recent`) for regressions

You can fetch the canonical checklist at runtime with:

```ruby
Agentf::Tools::SecurityScanner.new.best_practices
```

Adopting these practices keeps secrets out of your repo, enforces layered security checks, and helps the orchestration workflows remain resilient against prompt-injection attacks.
