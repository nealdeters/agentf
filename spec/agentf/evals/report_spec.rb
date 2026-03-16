# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Agentf::Evals::Report do
  let(:output_root) { Dir.mktmpdir("agentf-eval-report") }
  let(:history_path) { File.join(output_root, "history.jsonl") }

  after do
    FileUtils.remove_entry(output_root) if File.directory?(output_root)
  end

  it "summarizes providers, models, retries, and scenarios" do
    File.write(history_path, [
      JSON.generate({ "scenario" => "engineer_confirmation_retry", "status" => "passed", "providers" => ["direct-agent"], "models" => ["deterministic-cli"], "retry_count" => 1, "flaky" => true, "recorded_at" => "2026-03-16T19:00:00Z" }),
      JSON.generate({ "scenario" => "mcp_add_lesson", "status" => "passed", "providers" => ["mcp"], "models" => ["deterministic-cli"], "retry_count" => 0, "flaky" => false, "recorded_at" => "2026-03-16T19:01:00Z" })
    ].join("\n") + "\n")

    result = described_class.new(output_root: output_root).generate

    expect(result["count"]).to eq(2)
    expect(result.dig("retry_summary", "total_retries")).to eq(1)
    expect(result.dig("memory_effectiveness", "tracked_runs")).to eq(0)
    expect(result.dig("providers", "direct-agent", "flaky")).to eq(1)
    expect(result.dig("models", "deterministic-cli", "total")).to eq(2)
    expect(result.dig("scenarios", "engineer_confirmation_retry", "last_status")).to eq("passed")
  end

  it "supports since and scenario filtering" do
    File.write(history_path, [
      JSON.generate({ "scenario" => "old", "status" => "passed", "providers" => ["direct-agent"], "models" => ["deterministic-cli"], "retry_count" => 0, "flaky" => false, "recorded_at" => "2026-03-15T10:00:00Z" }),
      JSON.generate({ "scenario" => "new", "status" => "failed", "providers" => ["mcp"], "models" => ["deterministic-cli"], "retry_count" => 0, "flaky" => false, "recorded_at" => "2026-03-16T10:00:00Z" })
    ].join("\n") + "\n")

    result = described_class.new(output_root: output_root).generate(since: "2026-03-16T00:00:00Z", scenario: "new")

    expect(result["count"]).to eq(1)
    expect(result.dig("scenarios", "new", "failed")).to eq(1)
    expect(result["scenarios"]).not_to have_key("old")
  end

  it "summarizes memory effectiveness when present" do
    File.write(history_path, JSON.generate({
      "scenario" => "provider_runtime_copilot_recent",
      "status" => "passed",
      "providers" => ["copilot-runtime"],
      "models" => ["mcp-runtime"],
      "recorded_at" => "2026-03-16T12:00:00Z",
      "memory_effectiveness" => {
        "expected_titles" => ["Copilot runtime seeded lesson"],
        "matched_titles" => ["Copilot runtime seeded lesson"],
        "retrieved_expected_memory" => true
      }
    }) + "\n")

    result = described_class.new(output_root: output_root).generate

    expect(result.dig("memory_effectiveness", "tracked_runs")).to eq(1)
    expect(result.dig("memory_effectiveness", "retrieved_expected_memory")).to eq(1)
    expect(result.dig("scenarios", "provider_runtime_copilot_recent", "memory_retrieved")).to eq(1)
  end
end
