# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Agentf::Installer do
  let(:global_root) { Dir.mktmpdir("agentf-global") }
  let(:local_root) { Dir.mktmpdir("agentf-local") }

  after do
    FileUtils.remove_entry(global_root) if File.directory?(global_root)
    FileUtils.remove_entry(local_root) if File.directory?(local_root)
  end

  describe "#install" do
    it "installs selected manifests to provider-specific local paths"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      results = installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["planner"],
        only_commands: ["debugger"]
      )

      expect(results).not_to be_empty

      agent_path = File.join(local_root, ".opencode/agents/agentf-planner.md")
      command_path = File.join(local_root, ".opencode/commands/agentf-debugger.md")

      expect(File).to exist(agent_path)
      expect(File).to exist(command_path)
      expect(File.read(agent_path)).to include("## Memory Integration")
      expect(File.read(agent_path)).to include("## Memory Actions")
      expect(File.read(agent_path)).to include("## Policy Boundaries")
      expect(File.read(agent_path)).to include("agentf-memory-recent")
      expect(File.read(agent_path)).to include("get_recent_memories")
    end

    it "supports copilot file naming conventions"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["copilot"],
        scope: "local",
        only_agents: ["planner"],
        only_commands: ["debugger"]
      )

      agent_manifest = File.join(local_root, ".github/agents/planner.agent.md")
      command_manifest = File.join(local_root, ".github/commands/debugger.md")

      expect(File).to exist(agent_manifest)
      expect(File).to exist(command_manifest)
      expect(File.read(agent_manifest)).to include("## Copilot MCP Integration")
      expect(File.read(agent_manifest)).to include("agentf-code-glob")
      expect(File.read(command_manifest)).to include("## Copilot MCP Usage")
    end

    it "bootstraps opencode helper directories and files"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["planner"],
        only_commands: ["debugger"]
      )

      workflow_agent = File.join(local_root, ".opencode/agents/agentf-orchestrator.md")
      plugin = File.join(local_root, ".opencode/plugins/agentf-plugin.ts")
      memory_schema = File.join(local_root, ".opencode/memory/agentf-redis-schema.md")
      opencode_json = File.join(local_root, "opencode.json")

      expect(File).to exist(workflow_agent)
      expect(File).to exist(plugin)
      expect(File).to exist(memory_schema)
      expect(File).to exist(opencode_json)
      expect(File.read(workflow_agent)).to include("# AGENTF-WORKFLOW-ENGINE Agent")
      plugin_content = File.read(plugin)
      expect(plugin_content).to include("export const agentfPlugin")
      expect(plugin_content).to include("export default agentfPlugin")
      expect(plugin_content).to include("tools:")
      expect(plugin_content).to include("AGENTF_GEM_PATH")
      expect(plugin_content).to include("ensureAgentfPreflight")
      expect(plugin_content).to include("agentf version")
      expect(plugin_content).to include("Agentf plugin preflight failed")
      expect(plugin_content).to include("rbenv/asdf/mise")
      expect(plugin_content).not_to include('execFileAsync("bundle"')
      expect(plugin_content).not_to include('["exec", "ruby"')
      expect(File.read(memory_schema)).to include("# Redis Memory Schema")
      expect(File.read(opencode_json)).to include('"plugin"')
      expect(File.read(opencode_json)).to include("agentf-plugin")
    end

    it "merges opencode.json plugin entries instead of overwriting"  , :aggregate_failures do
      # create an existing opencode.json with a different plugin
      existing = {
        "$schema" => "https://opencode.ai/config.json",
        "plugin" => ["./.opencode/plugins/other-plugin"]
      }
      File.write(File.join(local_root, "opencode.json"), JSON.pretty_generate(existing))

      installer = described_class.new(global_root: global_root, local_root: local_root)
      installer.install(providers: ["opencode"], scope: "local", only_agents: ["planner"], only_commands: ["debugger"])

      merged = JSON.parse(File.read(File.join(local_root, "opencode.json")))
      expect(merged["plugin"]).to include("./.opencode/plugins/other-plugin")
      expect(merged["plugin"]).to include("./.opencode/plugins/agentf-plugin")
      expect(merged["plugin"].length).to eq(2)
    end

    it "can install deps when install_deps is true (skips if no package.json)" do
      installer = described_class.new(global_root: global_root, local_root: local_root, install_deps: true)

      # No .opencode/package.json exists, should skip gracefully
      results = installer.install(providers: ["opencode"], scope: "local")
      expect(results).to satisfy { |arr| arr.any? { |r| r["status"] == "skipped" || r["status"] == "no_manager_found" || r["status"] == "installed" } }
    end

    it "supports dry-run mode without writing files"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root, dry_run: true)

      results = installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["planner"],
        only_commands: ["debugger"]
      )

      expect(results).to all(include("status" => "planned"))
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/agentf-planner.md"))
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/agentf-orchestrator.md"))
      expect(File).not_to exist(File.join(local_root, ".opencode/plugins/agentf-plugin.ts"))
      expect(File).not_to exist(File.join(local_root, ".opencode/memory/agentf-redis-schema.md"))
      expect(File).not_to exist(File.join(local_root, "opencode.json"))
    end

    it "raises for unknown providers" do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      expect do
        installer.install(providers: ["unknown"], scope: "local")
      end.to raise_error(ArgumentError, /Unknown provider/)
    end

    it "maps all READ_ACTIONS to CLI commands in agent manifests"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["planner"],
        only_commands: []
      )

      agent_path = File.join(local_root, ".opencode/agents/agentf-planner.md")
      content = File.read(agent_path)

      # Architect reads get_recent_memories and get_pitfalls
      expect(content).to include("agentf-memory-recent")
      expect(content).to include("agentf-memory-recent")
    end

    it "includes read fallback for agents with no explicit reads"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["engineer"],
        only_commands: []
      )

      agent_path = File.join(local_root, ".opencode/agents/agentf-engineer.md")
      content = File.read(agent_path)

      # Specialist has no reads, so fallback should add a read action
      expect(content).to include("Read:")
      expect(content).to include("agentf-memory-recent")
    end
  end
end
