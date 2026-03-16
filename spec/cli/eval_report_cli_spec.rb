# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Agentf::CLI::Eval do
  let(:runner) { instance_double(Agentf::Evals::Runner) }

  subject(:cli) { described_class.new(runner: runner) }

  it "prints eval history summaries" do
    report = instance_double(Agentf::Evals::Report)
    allow(Agentf::Evals::Report).to receive(:new).and_return(report)
    allow(report).to receive(:generate).and_return(
      "count" => 3,
      "passes" => 2,
      "retry_summary" => { "total_retries" => 1, "flaky_runs" => 1 },
      "memory_effectiveness" => { "tracked_runs" => 1, "retrieved_expected_memory" => 1 },
      "providers" => { "mcp" => { "passed" => 1, "total" => 1 } },
      "models" => { "deterministic-cli" => { "passed" => 2, "total" => 3 } },
      "scenarios" => { "provider_runtime_copilot_recent" => { "passed" => 1, "failed" => 0, "retried" => 0, "flaky" => 0, "memory_retrieved" => 1 } }
    )

    expect { cli.run(["report"]) }
      .to output(include("Eval history").and(include("Retries:")).and(include("Memory retrieval:")).and(include("Scenario trends:")).and(include("mcp")))
      .to_stdout
  end

  it "passes through scenario and since filters" do
    report = instance_double(Agentf::Evals::Report)
    allow(Agentf::Evals::Report).to receive(:new).and_return(report)
    allow(report).to receive(:generate).with(limit: nil, since: "2026-03-16T00:00:00Z", scenario: "engineer_confirmation_retry").and_return(
      "count" => 0,
      "passes" => 0,
      "retry_summary" => { "total_retries" => 0, "flaky_runs" => 0 },
      "providers" => {},
      "models" => {}
    )

    capture_stdout { cli.run(["report", "--since=2026-03-16T00:00:00Z", "--scenario=engineer_confirmation_retry"]) }

    expect(report).to have_received(:generate).with(limit: nil, since: "2026-03-16T00:00:00Z", scenario: "engineer_confirmation_retry")
  end
end
