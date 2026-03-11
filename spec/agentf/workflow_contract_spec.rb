# frozen_string_literal: true

RSpec.describe Agentf::WorkflowContract do
  describe "#check" do
    it "passes when disabled"  , :aggregate_failures do
      contract = described_class.new(enabled: false, mode: "advisory")
      result = contract.check(stage: "spec", workflow_state: {})
      expect(result["ok"]).to be true
      expect(result["blocked"]).to be false
    end

    it "flags missing spec context"  , :aggregate_failures do
      contract = described_class.new(enabled: true, mode: "advisory")
      result = contract.check(stage: "spec", workflow_state: { "context" => {} })
      expect(result["ok"]).to be false
      expect(result["blocked"]).to be false
      expect(result["violations"].first["code"]).to eq("missing_spec_context")
    end

    it "blocks in enforcing mode" do
      contract = described_class.new(enabled: true, mode: "enforcing")
      result = contract.check(stage: "plan", workflow_state: {}, plan: { "agents_needed" => [] })
      expect(result["blocked"]).to be true
    end

    it "flags missing tdd red in execute stage" do
      contract = described_class.new(enabled: true, mode: "advisory")
      state = { "tdd" => { "enabled" => true, "red_executed" => false, "phase" => "red", "green_executed" => false } }
      result = contract.check(stage: "execute", workflow_state: state)
      expect(result["violations"].map { |v| v["code"] }).to include("tdd_red_not_executed")
    end
  end
end
