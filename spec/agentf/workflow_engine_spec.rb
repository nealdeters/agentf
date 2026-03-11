# frozen_string_literal: true

RSpec.describe Agentf::WorkflowEngine do
  let(:memory) do
    double(
      "memory",
      get_recent_memories: [],
      get_pitfalls: [],
      get_agent_context: {},
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
    around do |example|
      original = Agentf.config.metrics_enabled
      Agentf.config.metrics_enabled = true
      example.run
    ensure
      Agentf.config.metrics_enabled = original
    end

    it "runs workflow and captures feature intent"  , :aggregate_failures do
      engine = described_class.new(memory: memory, base_path: base_path, provider: :opencode)

      expect(memory).to receive(:store_feature_intent)
      result = engine.execute("Add feature")

      expect(result).to have_key("provider")
      expect(result["provider"]).to eq("OPENCODE")
      expect(result["workflow_contract"]).to be_a(Hash)
      expect(result["completed_agents"]).not_to be_empty
    end

    it "respects provided context"  , :aggregate_failures do
      engine = described_class.new(memory: memory, base_path: base_path, provider: :copilot)
      context = { "design_spec" => "Button component" }

      result = engine.execute("Create button", context: context)
      expect(result["pack"]).to eq("generic")
      expect(result["context"]).to eq(context)
    end

    it "resolves rails pack from context" do
      engine = described_class.new(memory: memory, base_path: base_path, provider: :opencode)
      result = engine.execute("Build rails feature", context: { "stack" => "rails" })
      expect(result["pack"]).to eq("rails_standard")
    end

    it "records workflow metrics via commands metrics recorder" do
      engine = described_class.new(memory: memory, base_path: base_path, provider: :opencode)
      metrics_commands = instance_double(Agentf::Commands::Metrics, record_workflow: { "status" => "recorded" })
      engine.instance_variable_set(:@metrics_commands, metrics_commands)

      expect(metrics_commands).to receive(:record_workflow).with(hash_including("provider" => "OPENCODE"))
      engine.execute("Add feature")
    end

    it "records memory confirmation events when persistence requires confirmation"  , :aggregate_failures do
      confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })

      memory_with_confirmation = double(
        "memory",
        get_recent_memories: [],
        get_pitfalls: [],
        get_agent_context: {},
        store_episode: nil,
        store_success: nil,
        store_pitfall: nil,
        store_lesson: nil,
        get_relevant_context: {}
      )

      allow(memory_with_confirmation).to receive(:store_feature_intent).and_raise(confirmation)

      engine = described_class.new(memory: memory_with_confirmation, base_path: base_path, provider: :opencode)

      result = engine.execute("Add feature")

      expect(result).to have_key("memory_confirmation_required")
      expect(result["memory_confirmation_required"]).to be_an(Array)
      expect(result["memory_confirmation_required"].length).to be >= 1
      first = result["memory_confirmation_required"].first
      expect(first["confirmation_required"]).to be(true)
      expect(first["confirmation_details"]).to eq(confirmation.details)
    end

    it "does not initialize metrics command when metrics are disabled" do
      Agentf.config.metrics_enabled = false
      engine = described_class.new(memory: memory, base_path: base_path, provider: :opencode)

      expect(engine.instance_variable_get(:@metrics_commands)).to be_nil
    end
  end
end
