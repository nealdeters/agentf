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
      content = File.read(agent_path)
      expect(content).to include("This manifest is a thin pointer.")
      expect(content).to include("IMPORTANT: Use the `agentf-planner` tool")
      expect(content).to include("Policy Summary:")
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
      mcp_config = File.join(local_root, ".vscode/mcp.json")

      expect(File).to exist(agent_manifest)
      expect(File).to exist(command_manifest)
      expect(File).to exist(mcp_config)
      expect(File.read(agent_manifest)).to include("This manifest is a thin pointer.")
      expect(File.read(agent_manifest)).to include("IMPORTANT: Use the `agentf-planner` tool")
      expect(File.read(command_manifest)).to include("This is a thin command manifest")
      expect(JSON.parse(File.read(mcp_config)).dig("servers", "agentf", "type")).to eq("stdio")
      expect(JSON.parse(File.read(mcp_config)).dig("servers", "agentf", "command")).to eq("agentf")
      expect(JSON.parse(File.read(mcp_config)).dig("servers", "agentf", "args")).to eq(["mcp-server"])
    end

    it "merges copilot mcp.json server entries instead of overwriting"  , :aggregate_failures do
      existing = {
        "servers" => {
          "other" => {
            "command" => "uvx",
            "args" => ["mcp-server-fetch"]
          }
        }
      }
      FileUtils.mkdir_p(File.join(local_root, ".vscode"))
      File.write(File.join(local_root, ".vscode/mcp.json"), JSON.pretty_generate(existing))

      installer = described_class.new(global_root: global_root, local_root: local_root)
      installer.install(providers: ["copilot"], scope: "local", only_agents: ["planner"], only_commands: ["debugger"])

      merged = JSON.parse(File.read(File.join(local_root, ".vscode/mcp.json")))
      expect(merged.dig("servers", "other", "command")).to eq("uvx")
      expect(merged.dig("servers", "agentf", "command")).to eq("agentf")
      expect(merged.dig("servers", "agentf", "args")).to eq(["mcp-server"])
    end

    it "bootstraps opencode mcp-first helper files by default"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root)

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["planner"],
        only_commands: ["debugger"]
      )

      workflow_agent = File.join(local_root, ".opencode/agents/agentf-orchestrator.md")
      memory_schema = File.join(local_root, ".opencode/memory/agentf-redis-schema.md")
      opencode_json = File.join(local_root, "opencode.json")

      expect(File).to exist(workflow_agent)
      expect(File).to exist(memory_schema)
      expect(File).to exist(opencode_json)
      expect(File.read(workflow_agent)).to include("# AGENTF-WORKFLOW-ENGINE Agent")
      expect(File.read(memory_schema)).to include("# Redis Memory Schema")
      opencode_config = JSON.parse(File.read(opencode_json))
      expect(opencode_config).to include("mcp")
      expect(opencode_config.dig("mcp", "agentf", "type")).to eq("local")
      expect(opencode_config.dig("mcp", "agentf", "command")).to eq([File.join(local_root, "bin", "agentf"), "mcp-server"])
      expect(File).not_to exist(File.join(local_root, ".opencode/plugins/agentf-plugin.ts"))
    end

    it "merges opencode.json mcp entries instead of overwriting"  , :aggregate_failures do
      existing = {
        "$schema" => "https://opencode.ai/config.json",
        "mcp" => {
          "other" => {
            "type" => "remote",
            "url" => "https://example.test/mcp"
          }
        }
      }
      File.write(File.join(local_root, "opencode.json"), JSON.pretty_generate(existing))

      installer = described_class.new(global_root: global_root, local_root: local_root)
      installer.install(providers: ["opencode"], scope: "local", only_agents: ["planner"], only_commands: ["debugger"])

      merged = JSON.parse(File.read(File.join(local_root, "opencode.json")))
      expect(merged.dig("mcp", "other", "url")).to eq("https://example.test/mcp")
      expect(merged.dig("mcp", "agentf", "command")).to eq([File.join(local_root, "bin", "agentf"), "mcp-server"])
    end

    it "removes the legacy agentf plugin entry when switching to mcp mode"  , :aggregate_failures do
      existing = {
        "$schema" => "https://opencode.ai/config.json",
        "plugin" => [
          "./.opencode/plugins/agentf-plugin",
          "./.opencode/plugins/other-plugin"
        ]
      }
      File.write(File.join(local_root, "opencode.json"), JSON.pretty_generate(existing))

      installer = described_class.new(global_root: global_root, local_root: local_root, opencode_runtime: "mcp")
      installer.install(providers: ["opencode"], scope: "local", only_agents: ["planner"], only_commands: ["debugger"])

      merged = JSON.parse(File.read(File.join(local_root, "opencode.json")))
      expect(merged.fetch("plugin")).to eq(["./.opencode/plugins/other-plugin"])
      expect(merged.dig("mcp", "agentf", "command")).to eq([File.join(local_root, "bin", "agentf"), "mcp-server"])
    end

    it "can still install the legacy opencode plugin runtime when requested"  , :aggregate_failures do
      installer = described_class.new(global_root: global_root, local_root: local_root, opencode_runtime: "plugin")

      installer.install(
        providers: ["opencode"],
        scope: "local",
        only_agents: ["planner"],
        only_commands: ["debugger"]
      )

      plugin = File.join(local_root, ".opencode/plugins/agentf-plugin.ts")
      opencode_json = JSON.parse(File.read(File.join(local_root, "opencode.json")))

      expect(File).to exist(plugin)
      expect(opencode_json["plugin"]).to include("./.opencode/plugins/agentf-plugin")
    end

    it "only installs opencode deps in legacy plugin mode"  , :aggregate_failures do
      default_installer = described_class.new(global_root: global_root, local_root: local_root, install_deps: true)
      default_results = default_installer.install(providers: ["opencode"], scope: "local")

      expect(default_results).not_to satisfy { |arr| arr.any? { |r| r["status"] == "skipped" || r["status"] == "no_manager_found" || r["status"] == "installed" } }

      plugin_installer = described_class.new(global_root: global_root, local_root: local_root, install_deps: true, opencode_runtime: "plugin")
      plugin_results = plugin_installer.install(providers: ["opencode"], scope: "local")

      expect(plugin_results).to satisfy { |arr| arr.any? { |r| r["status"] == "skipped" || r["status"] == "no_manager_found" || r["status"] == "installed" } }
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

      # Manifests are now thin pointers; ensure pointer and policy summary exist
      expect(content).to include("This manifest is a thin pointer.")
      expect(content).to include("Policy Summary:")
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

      # Manifests are thin pointers even for agents without explicit reads
      expect(content).to include("This manifest is a thin pointer.")
      expect(content).to include("Policy Summary:")
    end

    context "CLI fallback section for agents" do
      it "includes CLI fallback section in all provider agent manifests", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["opencode", "copilot"], scope: "local", only_agents: ["planner"], only_commands: [])

        opencode_content = File.read(File.join(local_root, ".opencode/agents/agentf-planner.md"))
        copilot_content = File.read(File.join(local_root, ".github/agents/planner.agent.md"))

        expect(opencode_content).to include("## CLI Fallback")
        expect(opencode_content).to include("If the `agentf` MCP server is unavailable")
        expect(copilot_content).to include("## CLI Fallback")
        expect(copilot_content).to include("If the `agentf` MCP server is unavailable")
      end

      it "includes agent CLI invocation in copilot fallback section", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["copilot"], scope: "local", only_agents: ["planner"], only_commands: [])

        content = File.read(File.join(local_root, ".github/agents/planner.agent.md"))

        expect(content).to include("`agentf agent planner \"<input>\"`")
      end

      it "includes standard memory read CLI commands in copilot fallback", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["copilot"], scope: "local", only_agents: ["planner"], only_commands: [])

        content = File.read(File.join(local_root, ".github/agents/planner.agent.md"))

        expect(content).to include("agentf memory recent -n 10")
        expect(content).to include("agentf memory search")
      end

      it "includes memory write fallback CLI commands when agent writes to memory", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["copilot"], scope: "local", only_agents: ["qa_tester"], only_commands: [])

        content = File.read(File.join(local_root, ".github/agents/qa_tester.agent.md"))

        expect(content).to include("**Memory writes**:")
        expect(content).to include("agentf memory add-episode")
        expect(content).to include("--agent=QA_TESTER")
      end

      it "omits memory write section for agents with no memory writes", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["copilot"], scope: "local", only_agents: ["planner"], only_commands: [])

        content = File.read(File.join(local_root, ".github/agents/planner.agent.md"))

        expect(content).not_to include("**Memory writes**:")
      end

      it "includes CLI fallback section in opencode agent manifests" do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["opencode"], scope: "local", only_agents: ["planner"], only_commands: [])

        content = File.read(File.join(local_root, ".opencode/agents/agentf-planner.md"))

        expect(content).to include("## CLI Fallback")
      end
    end

    context "CLI fallback section for commands" do
      it "includes CLI fallback section in all provider command manifests", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["opencode", "copilot"], scope: "local", only_agents: [], only_commands: ["explorer"])

        opencode_content = File.read(File.join(local_root, ".opencode/commands/agentf-explorer.md"))
        copilot_content = File.read(File.join(local_root, ".github/commands/explorer.md"))

        expect(opencode_content).to include("## CLI Fallback")
        expect(opencode_content).to include("If the `agentf` MCP server is unavailable")
        expect(copilot_content).to include("## CLI Fallback")
        expect(copilot_content).to include("If the `agentf` MCP server is unavailable")
      end

      it "includes explorer-specific code CLI commands", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["copilot"], scope: "local", only_agents: [], only_commands: ["explorer"])

        content = File.read(File.join(local_root, ".github/commands/explorer.md"))

        expect(content).to include("agentf code glob")
        expect(content).to include("agentf code grep")
        expect(content).to include("agentf code tree")
        expect(content).to include("agentf code related")
      end

      it "includes memory CLI commands for the memory command", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["copilot"], scope: "local", only_agents: [], only_commands: ["memory"])

        content = File.read(File.join(local_root, ".github/commands/memory.md"))

        expect(content).to include("agentf memory recent -n 10")
        expect(content).to include("agentf memory search")
        expect(content).to include("agentf memory add-lesson")
      end

      it "includes generic fallback for unspecialized commands", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["copilot"], scope: "local", only_agents: [], only_commands: ["debugger"])

        content = File.read(File.join(local_root, ".github/commands/debugger.md"))

        expect(content).to include("## CLI Fallback")
        expect(content).to include("agentf memory recent -n 10")
      end
    end

    context "TDD requirement section in agent manifests" do
      it "includes TDD Requirement section for code-writing agents", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["opencode"], scope: "local", only_agents: ["engineer"], only_commands: [])

        content = File.read(File.join(local_root, ".opencode/agents/agentf-engineer.md"))

        expect(content).to include("## TDD Requirement")
        expect(content).to include("Write the spec first")
        expect(content).to include("confirm red")
        expect(content).to include("confirm green")
        expect(content).to include("Showing test output")
      end

      it "includes TDD Requirement section for ui_engineer agent", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["opencode"], scope: "local", only_agents: ["ui_engineer"], only_commands: [])

        content = File.read(File.join(local_root, ".opencode/agents/agentf-ui_engineer.md"))

        expect(content).to include("## TDD Requirement")
      end

      it "includes TDD Requirement section for qa_tester agent", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["opencode"], scope: "local", only_agents: ["qa_tester"], only_commands: [])

        content = File.read(File.join(local_root, ".opencode/agents/agentf-qa_tester.md"))

        expect(content).to include("## TDD Requirement")
      end

      it "does not include TDD Requirement section for non-code-writing agents", :aggregate_failures do
        installer = described_class.new(global_root: global_root, local_root: local_root)
        installer.install(providers: ["opencode"], scope: "local", only_agents: ["planner", "incident_responder"], only_commands: [])

        planner_content = File.read(File.join(local_root, ".opencode/agents/agentf-planner.md"))
        debugger_content = File.read(File.join(local_root, ".opencode/agents/agentf-incident_responder.md"))

        expect(planner_content).not_to include("## TDD Requirement")
        expect(debugger_content).not_to include("## TDD Requirement")
      end
    end
  end
end
