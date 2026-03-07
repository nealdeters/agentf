# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Agentf::Installer do
  let(:global_root) { Dir.mktmpdir("agentf-global") }
  let(:local_root) { Dir.mktmpdir("agentf-local") }

  after do
    FileUtils.remove_entry(global_root) if File.directory?(global_root)
    FileUtils.remove_entry(local_root) if File.directory?(local_root)
  end

  describe "#install" do
    it "installs selected manifests to provider-specific local paths" do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      results = installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["architect"],
        only_commands: ["debugger"]
      )

      expect(results).not_to be_empty

      agent_path = File.join(local_root, ".opencode/agents/agentf-architect.md")
      command_path = File.join(local_root, ".opencode/commands/agentf-debugger.md")

      expect(File).to exist(agent_path)
      expect(File).to exist(command_path)
      expect(File.read(agent_path)).to include("## Memory Integration")
      expect(File.read(agent_path)).to include("## Memory Actions")
      expect(File.read(agent_path)).to include("## Policy Boundaries")
      expect(File.read(agent_path)).to include("agentf_memory_recent")
      expect(File.read(agent_path)).to include("get_recent_memories")
    end

    it "supports copilot file naming conventions" do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["copilot"],
        scope: "local",
        only_agents: ["architect"],
        only_commands: ["debugger"]
      )

      agent_manifest = File.join(local_root, ".github/agents/architect.agent.md")
      command_manifest = File.join(local_root, ".github/commands/debugger.md")

      expect(File).to exist(agent_manifest)
      expect(File).to exist(command_manifest)
      expect(File.read(agent_manifest)).to include("## Copilot MCP Integration")
      expect(File.read(agent_manifest)).to include("code_glob")
      expect(File.read(command_manifest)).to include("## Copilot MCP Usage")
    end

    it "bootstraps opencode helper directories and files" do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["architect"],
        only_commands: ["debugger"]
      )

      workflow_agent = File.join(local_root, ".opencode/agents/agentf-workflow-engine.md")
      plugin = File.join(local_root, ".opencode/plugins/agentf-plugin.ts")
      memory_schema = File.join(local_root, ".opencode/memory/agentf-redis-schema.md")
      opencode_json = File.join(local_root, "opencode.json")

      expect(File).to exist(workflow_agent)
      expect(File).to exist(plugin)
      expect(File).to exist(memory_schema)
      expect(File).to exist(opencode_json)
      expect(File.read(workflow_agent)).to include("# AGENTF-WORKFLOW-ENGINE Agent")
      expect(File.read(plugin)).to include("export const agentfPlugin")
      expect(File.read(plugin)).to include("AGENTF_GEM_PATH")
      expect(File.read(memory_schema)).to include("# Redis Memory Schema")
      expect(File.read(opencode_json)).to include('"plugin"')
      expect(File.read(opencode_json)).to include("agentf-plugin")
    end

    it "supports dry-run mode without writing files" do
      installer = described_class.new(global_root: global_root, local_root: local_root, dry_run: true)

      results = installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["architect"],
        only_commands: ["debugger"]
      )

      expect(results).to all(include("status" => "planned"))
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/agentf-architect.md"))
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/agentf-workflow-engine.md"))
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

    it "maps all READ_ACTIONS to CLI commands in agent manifests" do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["architect"],
        only_commands: []
      )

      agent_path = File.join(local_root, ".opencode/agents/agentf-architect.md")
      content = File.read(agent_path)

      # Architect reads get_recent_memories and get_pitfalls
      expect(content).to include("agentf_memory_recent")
      expect(content).to include("agentf_memory_recent")
    end

    it "includes read fallback for agents with no explicit reads" do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["specialist"],
        only_commands: []
      )

      agent_path = File.join(local_root, ".opencode/agents/agentf-specialist.md")
      content = File.read(agent_path)

      # Specialist has no reads, so fallback should add a read action
      expect(content).to include("Read:")
      expect(content).to include("agentf_memory_recent")
    end
  end
end
