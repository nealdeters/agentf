# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agentf::Commands::Metrics do
  let(:memory) { Agentf::Memory::RedisMemory.new(project: "test-project") }
  subject(:metrics) { described_class.new(memory: memory, project: "test-project") }

  describe ".manifest" do
    it "exposes command metadata" do
      manifest = described_class.manifest
      expect(manifest["name"]).to eq("metrics")
      command_names = manifest["commands"].map { |cmd| cmd["name"] }
      expect(command_names).to include("record_workflow", "summary", "provider_parity")
    end
  end

  describe "#record_workflow" do
    it "records workflow metrics as episodic memory" do
      workflow_state = {
        "provider" => "OPENCODE",
        "workflow_type" => "feature",
        "task" => "Add auth flow",
        "completed_agents" => %w[PLANNER ENGINEER REVIEWER],
        "results" => [
          { "agent" => "PLANNER", "result" => { "ok" => true } },
          { "agent" => "SECURITY_REVIEWER", "result" => { "issues" => [] } },
          { "agent" => "REVIEWER", "result" => { "approved" => true } }
        ]
      }

      result = metrics.record_workflow(workflow_state)
      expect(result["status"]).to eq("recorded")

      recent = memory.get_recent_memories(limit: 20)
      metric_memory = recent.find { |m| Array(m["tags"]).include?("workflow_metric") }
      expect(metric_memory).not_to be_nil
      expect(metric_memory["title"]).to include("OPENCODE")
      parsed = JSON.parse(metric_memory["context"])
      expect(parsed["provider"]).to eq("OPENCODE")
      expect(parsed["approved"]).to be true
    end
  end

  describe "#summary" do
    it "aggregates workflow quality metrics" do
      metrics.record_workflow(
        "provider" => "OPENCODE",
        "workflow_type" => "feature",
        "task" => "Feature A",
        "completed_agents" => %w[PLANNER REVIEWER],
        "results" => [
          { "agent" => "SECURITY_REVIEWER", "result" => { "issues" => [] } },
          { "agent" => "REVIEWER", "result" => { "approved" => true } }
        ]
      )

      metrics.record_workflow(
        "provider" => "COPILOT",
        "workflow_type" => "bugfix",
        "task" => "Bug B",
        "completed_agents" => %w[INCIDENT_RESPONDER REVIEWER],
        "results" => [
          { "agent" => "SECURITY_REVIEWER", "result" => { "issues" => [{ "issue" => "Potential Secret" }] } },
          { "agent" => "REVIEWER", "result" => { "approved" => false } }
        ]
      )

      summary = metrics.summary(limit: 50)
      expect(summary["total_runs"]).to be >= 2
      expect(summary).to have_key("completion_rate")
      expect(summary).to have_key("approval_rate")
      expect(summary).to have_key("security_issue_rate")
      expect(summary).to have_key("contract_adherence_rate")
      expect(summary).to have_key("policy_violation_rate")
      expect(summary["providers"]).to have_key("OPENCODE")
      expect(summary["providers"]).to have_key("COPILOT")
    end
  end

  describe "#provider_parity" do
    it "returns provider gap metrics" do
      metrics.record_workflow(
        "provider" => "OPENCODE",
        "workflow_type" => "feature",
        "task" => "Feature parity",
        "completed_agents" => %w[PLANNER REVIEWER],
        "results" => [
          { "agent" => "SECURITY_REVIEWER", "result" => { "issues" => [] } },
          { "agent" => "REVIEWER", "result" => { "approved" => true } }
        ]
      )

      metrics.record_workflow(
        "provider" => "COPILOT",
        "workflow_type" => "feature",
        "task" => "Feature parity",
        "completed_agents" => %w[PLANNER REVIEWER],
        "results" => [
          { "agent" => "SECURITY_REVIEWER", "result" => { "issues" => [] } },
          { "agent" => "REVIEWER", "result" => { "approved" => false } }
        ]
      )

      parity = metrics.provider_parity(limit: 50)
      expect(parity["providers_present"]).to include("OPENCODE", "COPILOT")
      expect(parity).to have_key("completion_rate_gap")
      expect(parity).to have_key("approval_rate_gap")
      expect(parity).to have_key("security_issue_rate_gap")
      expect(parity).to have_key("avg_agents_gap")
    end
  end
end
