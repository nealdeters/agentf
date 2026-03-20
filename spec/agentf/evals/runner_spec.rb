# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Agentf::Evals::Runner do
  let(:eval_root) { Dir.mktmpdir("agentf-evals") }
  let(:output_root) { Dir.mktmpdir("agentf-eval-output") }
  let(:runner) { described_class.new(root: eval_root, output_root: output_root, agentf_bin: "/tmp/agentf") }
  let(:status_success) { instance_double(Process::Status, success?: true, exitstatus: 0) }

  after do
    FileUtils.remove_entry(eval_root) if File.directory?(eval_root)
    FileUtils.remove_entry(output_root) if File.directory?(output_root)
  end

  describe "#list" do
    it "discovers scenario metadata from the eval root" do
      write_scenario("engineer_episode_positive", agent: "engineer")

      scenarios = runner.list

      expect(scenarios.map(&:name)).to eq(["engineer_episode_positive"])
      expect(scenarios.first.agent).to eq("engineer")
    end
  end

  describe "scenario metadata" do
    it "captures execution mode, retry settings, and matrix metadata" do
      write_scenario(
        "engineer_confirmation_retry",
        agent: "engineer",
        extra_yaml: <<~YAML
          execution_mode: agent
          retry_on_confirmation: true
          confirmed_write_token: retry-approved
          providers:
            - direct-agent
          models:
            - deterministic-cli
        YAML
      )

      scenario = runner.list.first

      expect(scenario.execution_mode).to eq("agent")
      expect(scenario.retry_on_confirmation?).to be(true)
      expect(scenario.confirmed_write_token).to eq("retry-approved")
      expect(scenario.providers).to eq(["direct-agent"])
      expect(scenario.models).to eq(["deterministic-cli"])
    end
  end

  describe "#run" do
    it "runs setup, agent, and verify steps and writes artifacts" do
      write_scenario("planner_reads_seeded_pitfall", agent: "planner", with_setup: true)

      allow(Open3).to receive(:capture3)
        .and_return(
          ["setup complete", "", status_success],
          [JSON.generate({ "subtasks" => [{ "id" => 1 }], "context" => { "pitfalls_to_avoid" => [{ "title" => "Avoid broad rescues" }] } }), "", status_success],
          ["verify complete", "", status_success]
        )

      result = runner.run(name: "planner_reads_seeded_pitfall", keep_workspace: true)

      expect(result["passed"]).to eq(1)
      expect(result["failed"]).to eq(0)
      scenario_result = result["results"].first
      expect(scenario_result["status"]).to eq("passed")
      expect(scenario_result.dig("agent_run", "parsed_output", "context", "pitfalls_to_avoid").first["title"]).to eq("Avoid broad rescues")
      expect(File).to exist(File.join(scenario_result["artifact_dir"], "summary.json"))
      expect(File).to exist(File.join(scenario_result["artifact_dir"], "agent_result.json"))
      expect(Dir).to exist(scenario_result["workspace"])
    end

    it "marks the scenario failed when verify exits non-zero" do
      write_scenario("engineer_episode_positive", agent: "engineer")
      failed_status = instance_double(Process::Status, success?: false, exitstatus: 1)

      allow(Open3).to receive(:capture3)
        .and_return(
          [JSON.generate({ "success" => true }), "", status_success],
          ["", "verification failed", failed_status]
        )

      result = runner.run(name: "engineer_episode_positive")

      expect(result["passed"]).to eq(0)
      expect(result["failed"]).to eq(1)
      expect(result["results"].first["failure_step"]).to eq("verify")
    end

    it "retries agent execution after confirmation-required responses" do
      write_scenario(
        "engineer_confirmation_retry",
        agent: "engineer",
        extra_yaml: <<~YAML
          retry_on_confirmation: true
          confirmed_write_token: retry-approved
          providers:
            - direct-agent
          models:
            - deterministic-cli
        YAML
      )

      allow(Open3).to receive(:capture3)
        .and_return(
          [JSON.generate({ "confirmation_required" => true }), "", status_success],
          [JSON.generate({ "success" => true }), "", status_success],
          ["verify complete", "", status_success]
        )

      result = runner.run(name: "engineer_confirmation_retry")
      scenario_result = result["results"].first

      expect(scenario_result.dig("agent_run", "parsed_output", "success")).to be(true)
      expect(scenario_result.dig("verify", "status")).to eq("passed")
      expect(scenario_result["providers"]).to eq(["direct-agent"])
      expect(result.dig("matrix", "providers", "direct-agent", "passed")).to eq(1)
      expect(File).to exist(File.join(output_root, "history.jsonl"))
    end

    it "supports in-process MCP execution" do
      write_scenario(
        "mcp_recent_memories",
        agent: nil,
        extra_yaml: <<~YAML,
          execution_mode: mcp
          mcp_tool: agentf-memory-recent
          prompt_format: json
        YAML
        prompt: '{"limit":5}'
      )

      server = instance_double(Agentf::MCP::Server)
      stubbed_tools = instance_double(Agentf::MCP::Server::RegistryAdapter)
      allow(Agentf::MCP::Server).to receive(:new).and_return(server)
      allow(server).to receive(:server).and_return(stubbed_tools)
      allow(stubbed_tools).to receive(:call_tool).with("agentf-memory-recent", **{ limit: 5 }).and_return(JSON.generate({ "count" => 1, "memories" => [{ "title" => "Seeded" }] }))
      allow(Open3).to receive(:capture3).and_return(["verify complete", "", status_success])

      result = runner.run(name: "mcp_recent_memories")
      scenario_result = result["results"].first

      expect(scenario_result["execution_mode"]).to eq("mcp")
      expect(scenario_result.dig("agent_run", "parsed_output", "count")).to eq(1)
    end

    it "supports provider execution with installer pre-step" do
      write_scenario(
        "provider_install_opencode",
        agent: nil,
        extra_yaml: <<~YAML,
          execution_mode: provider
          provider: opencode
          provider_scope: local
          provider_install_deps: false
          prompt_format: json
          providers:
            - opencode
          models:
            - manifest-install
        YAML
        prompt: '{"command":["memory","recent","-n","1","--json"]}'
      )

      installer = instance_double(Agentf::Installer)
      allow(Agentf::Installer).to receive(:new).and_return(installer)
      allow(installer).to receive(:install).and_return([
        { "path" => "/tmp/work/.opencode/agents/agentf-planner.md", "status" => "written" }
      ])
      allow(Open3).to receive(:capture3)
        .and_return([JSON.generate({ "count" => 0, "memories" => [] }), "", status_success], ["verify complete", "", status_success])

      result = runner.run(name: "provider_install_opencode")
      scenario_result = result["results"].first

      expect(scenario_result["execution_mode"]).to eq("provider")
      expect(scenario_result.dig("agent_run", "install", "status")).to eq("passed")
      expect(scenario_result.dig("agent_run", "parsed_output", "count")).to eq(0)
    end

    it "supports provider runtime execution against generated plugin tools" do
      write_scenario(
        "provider_runtime_opencode_recent",
        agent: nil,
        extra_yaml: <<~YAML,
          execution_mode: provider_runtime
          provider: opencode
          provider_runtime_tool: agentf-memory-recent
          provider_scope: local
          provider_install_deps: false
          prompt_format: json
          providers:
            - opencode-runtime
          models:
            - plugin-runtime
        YAML
        prompt: '{"input":{"limit":5}}'
      )

      installer = instance_double(Agentf::Installer)
      allow(Agentf::Installer).to receive(:new).and_return(installer)
      allow(installer).to receive(:install).and_return([
        { "path" => "/tmp/work/.opencode/plugins/agentf-plugin.ts", "status" => "written" }
      ])
      allow(runner).to receive(:render_opencode_eval_driver).and_return("process.stdout.write(JSON.stringify({ memories: [{ title: 'Seeded' }], count: 1 }));")
      allow(Open3).to receive(:capture3).and_return([JSON.generate({ "memories" => [{ "title" => "Seeded" }], "count" => 1 }), "", status_success], ["verify complete", "", status_success])

      result = runner.run(name: "provider_runtime_opencode_recent")
      scenario_result = result["results"].first

      expect(scenario_result["execution_mode"]).to eq("provider_runtime")
      expect(scenario_result.dig("agent_run", "parsed_output", "count")).to eq(1)
    end

    it "records memory effectiveness for expected runtime retrieval" do
      write_scenario(
        "provider_runtime_copilot_recent",
        agent: nil,
        extra_yaml: <<~YAML,
          execution_mode: provider_runtime
          provider: copilot
          provider_runtime_tool: agentf-memory-recent
          provider_scope: local
          prompt_format: json
          expected_memory_titles:
            - Copilot runtime seeded lesson
        YAML
        prompt: '{"input":{"limit":5}}'
      )

      installer = instance_double(Agentf::Installer)
      allow(Agentf::Installer).to receive(:new).and_return(installer)
      allow(installer).to receive(:install).and_return([{ "path" => "/tmp/work/.github/agents/planner.agent.md", "status" => "written" }])
      fake_server = instance_double(Agentf::MCP::Server)
      fake_mcp = instance_double(Agentf::MCP::Server::RegistryAdapter)
      allow(Agentf::MCP::Server).to receive(:new).and_return(fake_server)
      allow(fake_server).to receive(:server).and_return(fake_mcp)
      allow(fake_mcp).to receive(:call_tool).with("agentf-memory-recent", **{ limit: 5 }).and_return(JSON.generate({ "memories" => [{ "title" => "Copilot runtime seeded lesson" }], "count" => 1 }))
      allow(Open3).to receive(:capture3).and_return(["verify complete", "", status_success])

      result = runner.run(name: "provider_runtime_copilot_recent")

      expect(result.dig("results", 0, "memory_effectiveness", "retrieved_expected_memory")).to be(true)
    end
  end

  def write_scenario(name, agent:, with_setup: false, extra_yaml: nil, prompt: "hello world")
    dir = File.join(eval_root, name)
    FileUtils.mkdir_p(dir)
    lines = ["name: #{name}", "description: Example scenario"]
    lines << "agent: #{agent}" if agent
    lines << extra_yaml.to_s.strip unless extra_yaml.to_s.strip.empty?
    File.write(File.join(dir, "scenario.yml"), lines.join("\n") + "\n")
    File.write(File.join(dir, "prompt.txt"), prompt)
    File.write(File.join(dir, "verify.sh"), "exit 0\n")
    File.write(File.join(dir, "setup.sh"), "exit 0\n") if with_setup
  end
end
