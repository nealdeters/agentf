# frozen_string_literal: true

RSpec.describe Agentf::ContextBuilder do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  subject(:builder) { described_class.new(memory: memory) }

  describe "#build" do
    it "delegates to memory get_agent_context"  , :aggregate_failures do
      workflow_state = { "task" => "Fix payment bug", "workflow_type" => "bugfix" }
      payload = { "agent" => "INCIDENT_RESPONDER", "memories" => [] }

      expect(memory).to receive(:get_agent_context).with(
        agent: "INCIDENT_RESPONDER",
        task_type: "bugfix",
        query_embedding: be_an(Array),
        limit: 6
      ).and_return(payload)

      result = builder.build(agent: "INCIDENT_RESPONDER", workflow_state: workflow_state, limit: 6)
      expect(result).to eq(payload)
    end

    it "returns safe fallback on memory failures"  , :aggregate_failures do
      allow(memory).to receive(:get_agent_context).and_raise("boom")

      result = builder.build(agent: "PLANNER", workflow_state: { "task" => "Add feature", "workflow_type" => "feature" })
      expect(result["agent"]).to eq("PLANNER")
      expect(result["memories"]).to eq([])
    end
  end
end
