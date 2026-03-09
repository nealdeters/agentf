# frozen_string_literal: true

RSpec.describe Agentf::AgentExecutionContract do
  let(:policy) { Agentf::AgentPolicy.new }
  let(:boundaries) do
    {
      "required_inputs" => ["description"],
      "required_outputs" => ["subtask_id", "success"]
    }
  end

  it "raises in enforcing mode when required inputs are missing" do
    contract = described_class.new(enabled: true, mode: "enforcing", policy: policy)

    expect do
      contract.before!(agent_name: Agentf::AgentRoles::ENGINEER, boundaries: boundaries, context: {})
    end.to raise_error(Agentf::AgentContractViolation)
  end

  it "does not raise in advisory mode for violations" do
    contract = described_class.new(enabled: true, mode: "advisory", policy: policy)

    expect do
      contract.before!(agent_name: Agentf::AgentRoles::ENGINEER, boundaries: boundaries, context: {})
    end.not_to raise_error
  end

  it "enforces TDD green expected signature for implementation agents" do
    contract = described_class.new(enabled: true, mode: "enforcing", policy: policy)

    expect do
      contract.after!(
        agent_name: Agentf::AgentRoles::ENGINEER,
        boundaries: boundaries,
        context: { "description" => "Implement", "tdd_phase" => "green" },
        result: { "subtask_id" => "1", "success" => true }
      )
    end.to raise_error(Agentf::AgentContractViolation)
  end

  it "enforces boolean success for coding agents" do
    contract = described_class.new(enabled: true, mode: "enforcing", policy: policy)

    expect do
      contract.after!(
        agent_name: Agentf::AgentRoles::UI_ENGINEER,
        boundaries: { "required_outputs" => ["component", "generated_code", "success"] },
        context: { "design_spec" => "Card" },
        result: { "component" => "Card", "generated_code" => "code", "success" => "yes" }
      )
    end.to raise_error(Agentf::AgentContractViolation)
  end
end
