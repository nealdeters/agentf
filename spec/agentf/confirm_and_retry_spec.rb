# frozen_string_literal: true

require "spec_helper"

RSpec.describe "confirm and retry flow" do
  let(:base_path) { File.expand_path("../fixtures", __dir__) }

  it "captures confirmation_required then succeeds when retried with confirm" do
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })

    memory = double(
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

    # On first attempt (no confirm), raise ConfirmationRequired. When called with
    # confirm: true, return a persisted episode id.
    allow(memory).to receive(:store_feature_intent) do |**kwargs|
      if kwargs[:confirm] == true
        "episode_confirmed"
      else
        raise confirmation
      end
    end

    engine = Agentf::WorkflowEngine.new(memory: memory, base_path: base_path, provider: :opencode)

    # First execution should record a memory_confirmation_required entry
    result = engine.execute(task: "Add feature")
    expect(result).to have_key("memory_confirmation_required")
    expect(result["memory_confirmation_required"]).to be_an(Array)
    first = result["memory_confirmation_required"].first
    expect(first["confirmation_required"]).to be(true)
    expect(first["confirmation_details"]).to eq(confirmation.details)

    # Simulate user confirming the write and retrying the memory write directly
    persisted = memory.store_feature_intent(title: "Add feature", description: "Workflow intent captured by workflow engine", confirm: true)
    expect(persisted).to eq("episode_confirmed")
  end
end
