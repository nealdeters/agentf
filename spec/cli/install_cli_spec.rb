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
    it "installs opencode manifests to local directory" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}",
          "--agent=architect",
          "--command=debugger"
        ])
      end

      expect(output).to include("Completed")
      expect(File).to exist(File.join(local_root, ".opencode/agents/agentf-architect.md"))
      expect(File).to exist(File.join(local_root, ".opencode/commands/agentf-debugger.md"))
    end
  end

  describe "--dry-run" do
    it "reports planned operations without writing files" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}",
          "--agent=architect",
          "--dry-run"
        ])
      end

      expect(output).to include("PLANNED")
      expect(File).not_to exist(File.join(local_root, ".opencode/agents/agentf-architect.md"))
    end
  end

  describe "provider parsing" do
    it "accepts comma-separated providers" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode,copilot",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}",
          "--agent=architect"
        ])
      end

      expect(output).to include("Completed")
      expect(File).to exist(File.join(local_root, ".opencode/agents/agentf-architect.md"))
      expect(File).to exist(File.join(local_root, ".github/agents/architect.agent.md"))
    end
  end

  describe "help" do
    it "prints help text" do
      output = capture_stdout { cli.run(["help"]) }

      expect(output).to include("Usage: agentf install")
      expect(output).to include("--provider")
      expect(output).to include("--dry-run")
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
