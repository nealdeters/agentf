# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Agentf::CLI::Metrics do
  let(:metrics) { instance_double(Agentf::Commands::Metrics) }

  subject(:cli) { described_class.new(metrics: metrics) }

  describe "summary command" do
    it "prints summary output" do
      allow(metrics).to receive(:summary).with(limit: 10).and_return(
        "project" => "test-project",
        "total_runs" => 5,
        "completion_rate" => 0.8,
        "approval_rate" => 0.6,
        "failure_rate" => 0.2,
        "security_issue_rate" => 0.4,
        "avg_agents_executed" => 6.2,
        "contract_adherence_rate" => 0.9,
        "contract_blocked_runs" => 1,
        "policy_violation_rate" => 0.1
      )

      expect { cli.run(["summary"]) }
        .to output(include("Workflow Metrics Summary (test-project)")).to_stdout
    end

    it "returns JSON when requested" do
      allow(metrics).to receive(:summary).with(limit: 20).and_return(
        "project" => "test-project",
        "total_runs" => 20,
        "completion_rate" => 0.9,
        "approval_rate" => 0.7,
        "failure_rate" => 0.1,
        "security_issue_rate" => 0.2,
        "avg_agents_executed" => 5.5,
        "contract_adherence_rate" => 1.0,
        "contract_blocked_runs" => 0,
        "policy_violation_rate" => 0.0
      )

      output = capture_stdout { cli.run(["summary", "-n", "20", "--json"]) }
      payload = JSON.parse(output)
      expect(payload["total_runs"]).to eq(20)
    end
  end

  describe "parity command" do
    it "prints parity output" do
      allow(metrics).to receive(:provider_parity).with(limit: 10).and_return(
        "project" => "test-project",
        "opencode_runs" => 8,
        "copilot_runs" => 8,
        "completion_rate_gap" => 0.1,
        "approval_rate_gap" => 0.05,
        "security_issue_rate_gap" => -0.1,
        "avg_agents_gap" => 1.0
      )

      expect { cli.run(["parity"]) }
        .to output(include("Provider Parity (test-project)")).to_stdout
    end
  end

  describe "help" do
    it "prints help text" do
      expect { cli.run(["help"]) }
        .to output(include("Usage: agentf metrics <command>")).to_stdout
    end
  end

  def capture_stdout
    original = $stdout
    io = StringIO.new
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end
end
