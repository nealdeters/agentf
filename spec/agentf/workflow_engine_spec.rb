# frozen_string_literal: true

RSpec.describe Agentf::WorkflowEngine do
  let(:memory) do
    double(
      "memory",
      get_recent_memories: [],
      get_pitfalls: [],
      store_episode: nil,
      store_success: nil,
      store_pitfall: nil,
      store_lesson: nil,
      store_feature_intent: nil,
      get_relevant_context: {}
    )
  end
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }

  describe "provider selection" do
    it "uses opencode adapter by default" do
      engine = described_class.new(memory: memory, base_path: base_path)
      expect(engine.provider).to be_a(Agentf::Service::Providers::OpenCode)
    end

    it "accepts copilot adapter" do
      engine = described_class.new(memory: memory, base_path: base_path, provider: :copilot)
      expect(engine.provider).to be_a(Agentf::Service::Providers::Copilot)
    end

    it "raises on unknown provider" do
      expect do
        described_class.new(memory: memory, base_path: base_path, provider: :unknown)
      end.to raise_error(ArgumentError, /Unknown provider/)
    end
  end

  describe "#execute" do
    it "runs workflow and captures feature intent" do
      engine = described_class.new(memory: memory, base_path: base_path, provider: :opencode)

      expect(memory).to receive(:store_feature_intent)
      result = engine.execute("Add feature")

      expect(result).to have_key("provider")
      expect(result["provider"]).to eq("OPENCODE")
      expect(result["completed_agents"]).not_to be_empty
    end

    it "respects provided context" do
      engine = described_class.new(memory: memory, base_path: base_path, provider: :copilot)
      context = { "design_spec" => "Button component" }

      result = engine.execute("Create button", context: context)
      expect(result["context"]).to eq(context)
    end
  end
end
