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

      agent_path = File.join(local_root, ".opencode/agents/ARCHITECT.md")
      command_path = File.join(local_root, ".opencode/commands/debugger.md")

      expect(File).to exist(agent_path)
      expect(File).to exist(command_path)
      expect(File.read(agent_path)).to include("## Memory Integration")
      expect(File.read(agent_path)).to include("## Memory Actions")
      expect(File.read(agent_path)).to include("agentf memory recent -n 10")
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

      workflow_agent = File.join(local_root, ".opencode/agents/WORKFLOW_ENGINE.md")
      tools_wrapper = File.join(local_root, ".opencode/tools/agentf-tools.ts")
      memory_schema = File.join(local_root, ".opencode/memory/REDIS_SCHEMA.md")

      expect(File).to exist(workflow_agent)
      expect(File).to exist(tools_wrapper)
      expect(File).to exist(memory_schema)
      expect(File.read(workflow_agent)).to include("# WORKFLOW_ENGINE Agent")
      expect(File.read(tools_wrapper)).to include("export const AgentfToolsPlugin")
      expect(File.read(memory_schema)).to include("# Redis Memory Schema")
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
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/ARCHITECT.md"))
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/WORKFLOW_ENGINE.md"))
      expect(File).not_to exist(File.join(local_root, ".opencode/tools/agentf-tools.ts"))
      expect(File).not_to exist(File.join(local_root, ".opencode/memory/REDIS_SCHEMA.md"))
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

      agent_path = File.join(local_root, ".opencode/agents/ARCHITECT.md")
      content = File.read(agent_path)

      # Architect reads get_recent_memories and get_pitfalls
      expect(content).to include("agentf memory recent")
      expect(content).to include("agentf memory pitfalls")
    end

    it "includes read fallback for agents with no explicit reads" do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["specialist"],
        only_commands: []
      )

      agent_path = File.join(local_root, ".opencode/agents/SPECIALIST.md")
      content = File.read(agent_path)

      # Specialist has no reads, so fallback should add a read action
      expect(content).to include("Read:")
      expect(content).to include("agentf memory recent")
    end
  end
end
