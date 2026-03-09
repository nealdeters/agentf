# frozen_string_literal: true

RSpec.describe Agentf::AgentPolicy do
  subject(:policy) { described_class.new }

  it "returns no violations when requirements are met" do
    boundaries = {
      "required_inputs" => ["source_file"]
    }

    violations = policy.validate(
      agent_name: "QA_TESTER",
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
      agent_name: "QA_TESTER",
      boundaries: boundaries,
      context: {},
      result: {}
    )

    expect(violations.first["code"]).to eq("missing_required_inputs")
  end

  it "reports missing required outputs" do
    boundaries = {
      "required_outputs" => ["approved", "issues"]
    }

    violations = policy.validate(
      agent_name: "REVIEWER",
      boundaries: boundaries,
      context: {},
      result: { "approved" => true },
      phase: :after
    )

    expect(violations.map { |v| v["code"] }).to include("missing_required_outputs")
  end
end
