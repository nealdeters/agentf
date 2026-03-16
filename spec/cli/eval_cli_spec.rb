# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Agentf::CLI::Eval do
  let(:runner) { instance_double(Agentf::Evals::Runner) }

  subject(:cli) { described_class.new(runner: runner) }

  describe "list" do
    it "prints discovered scenarios" do
      scenario = instance_double(
        Agentf::Evals::Scenario,
        name: "engineer_store_success",
        execution_mode: "agent",
        mcp_tool: nil,
        agent: "engineer",
        description: "Stores a success memory",
        to_h: { "name" => "engineer_store_success" }
      )
      allow(runner).to receive(:list).and_return([scenario])

      expect { cli.run(["list"]) }
        .to output(include("engineer_store_success").and(include("engineer")))
        .to_stdout
    end

    it "supports json output" do
      scenario = instance_double(
        Agentf::Evals::Scenario,
        name: "engineer_store_success",
        execution_mode: "agent",
        mcp_tool: nil,
        agent: "engineer",
        description: "Stores a success memory",
        to_h: { "name" => "engineer_store_success", "agent" => "engineer" }
      )
      allow(runner).to receive(:list).and_return([scenario])

      output = capture_stdout { cli.run(["list", "--json"]) }
      payload = JSON.parse(output)

      expect(payload["count"]).to eq(1)
      expect(payload.dig("scenarios", 0, "name")).to eq("engineer_store_success")
    end
  end

  describe "run" do
    it "prints a pass summary for successful evals" do
      allow(runner).to receive(:run).and_return(
        "count" => 1,
        "passed" => 1,
        "failed" => 0,
        "matrix" => {
          "providers" => { "direct-agent" => { "total" => 1, "passed" => 1, "failed" => 0 } },
          "models" => { "deterministic-cli" => { "total" => 1, "passed" => 1, "failed" => 0 } }
        },
        "results" => [
          {
            "scenario" => "engineer_store_success",
            "status" => "passed",
            "artifact_dir" => "/tmp/evals/engineer_store_success",
            "failure_step" => nil
          }
        ]
      )

      expect { cli.run(["run", "engineer_store_success"]) }
        .to output(include("1/1 passed").and(include("engineer_store_success")).and(include("Provider matrix")).and(include("Model matrix")))
        .to_stdout
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
