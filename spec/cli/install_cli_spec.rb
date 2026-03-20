# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe Agentf::CLI::Install do
  let(:global_root) { Dir.mktmpdir("agentf-global") }
  let(:local_root) { Dir.mktmpdir("agentf-local") }

  after do
    FileUtils.remove_entry(global_root) if File.directory?(global_root)
    FileUtils.remove_entry(local_root) if File.directory?(local_root)
  end

  subject(:cli) { described_class.new }

  describe "install with defaults" do
    it "installs opencode manifests to local directory"  , :aggregate_failures do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}",
          "--agent=planner",
          "--command=debugger"
        ])
      end

      expect(output).to include("Completed")
      expect(File).to exist(File.join(local_root, ".opencode/agents/agentf-planner.md"))
      expect(File).to exist(File.join(local_root, ".opencode/commands/agentf-debugger.md"))
      expect(JSON.parse(File.read(File.join(local_root, "opencode.json"))).dig("mcp", "agentf", "command")).to eq([File.join(local_root, "bin", "agentf"), "mcp-server"])
      expect(File).not_to exist(File.join(local_root, ".opencode/plugins/agentf-plugin.ts"))
    end
  end

  describe "--dry-run" do
    it "reports planned operations without writing files"  , :aggregate_failures do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}",
          "--agent=planner",
          "--dry-run"
        ])
      end

      expect(output).to include("PLANNED")
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/agentf-planner.md"))
    end
  end

  describe "provider parsing" do
    it "accepts comma-separated providers"  , :aggregate_failures do
      output = capture_stdout do
        cli.run([
          "--provider=opencode,copilot",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}",
          "--agent=planner"
        ])
      end

      expect(output).to include("Completed")
      expect(File).to exist(File.join(local_root, ".opencode/agents/agentf-planner.md"))
      expect(File).to exist(File.join(local_root, ".github/agents/planner.agent.md"))
      expect(JSON.parse(File.read(File.join(local_root, ".vscode/mcp.json"))).dig("servers", "agentf", "args")).to eq(["mcp-server"])
    end
  end

  describe "opencode runtime selection" do
    it "supports the legacy plugin runtime when requested"  , :aggregate_failures do
      capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}",
          "--agent=planner",
          "--opencode-runtime=plugin"
        ])
      end

      expect(File).to exist(File.join(local_root, ".opencode/plugins/agentf-plugin.ts"))
      expect(JSON.parse(File.read(File.join(local_root, "opencode.json")))["plugin"]).to include("./.opencode/plugins/agentf-plugin")
    end
  end

  describe "help" do
    it "prints help text"  , :aggregate_failures do
      output = capture_stdout { cli.run(["help"]) }

      expect(output).to include("Usage: agentf install")
      expect(output).to include("--provider")
      expect(output).to include("--dry-run")
      expect(output).to include("--opencode-runtime")
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
