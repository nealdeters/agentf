# frozen_string_literal: true

RSpec.describe Agentf::AgentPolicy do
  subject(:policy) { described_class.new }

  it "returns no violations when requirements are met" do
    boundaries = {
      "required_inputs" => ["source_file"]
    }

    violations = policy.validate(
      agent_name: "TESTER",
      boundaries: boundaries,
      context: { "source_file" => "app/models/user.rb" },
      result: { "passed" => true }
    )

    expect(violations).to eq([])
  end

  it "reports missing required inputs" do
    boundaries = {
      "required_inputs" => ["source_file"]
    }

    violations = policy.validate(
      agent_name: "TESTER",
      boundaries: boundaries,
      context: {},
      result: {}
    )

    expect(violations.first["code"]).to eq("missing_required_inputs")
  end
end
