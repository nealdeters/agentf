# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe Agentf::CLI::Update do
  let(:root) { Dir.mktmpdir("agentf-update") }
  let(:stamp_dir) { File.join(root, ".opencode") }
  let(:stamp_path) { File.join(stamp_dir, ".agentf-version") }

  # A fake installer that records calls and returns predictable results.
  let(:fake_installer_class) do
    Class.new do
      attr_reader :install_calls

      def initialize(global_root:, local_root:)
        @global_root = global_root
        @local_root = local_root
        @install_calls = []
      end

      def install(providers:, scope:)
        @install_calls << { providers: providers, scope: scope }
        providers.map do |p|
          { "status" => "created", "path" => File.join(@local_root, ".#{p}/agents/PLANNER.md") }
        end
      end
    end
  end

  # Track instances created by fake_installer_class so we can inspect them.
  let(:installer_instances) { [] }
  let(:tracking_installer_class) do
    instances = installer_instances
    klass = fake_installer_class
    Class.new(klass) do
      define_method(:initialize) do |global_root:, local_root:|
        super(global_root: global_root, local_root: local_root)
        instances << self
      end
    end
  end

  subject(:cli) { described_class.new(installer_class: tracking_installer_class) }

  after do
    FileUtils.remove_entry(root) if File.directory?(root)
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

  describe "help" do
    it "prints help text" do
      output = capture_stdout { cli.run(["help"]) }

      expect(output).to include("Usage: agentf update")
      expect(output).to include("--provider")
      expect(output).to include("--force")
      expect(output).to include("--scope")
    end

    it "prints help for --help flag" do
      output = capture_stdout { cli.run(["--help"]) }
      expect(output).to include("Usage: agentf update")
    end

    it "prints help for -h flag" do
      output = capture_stdout { cli.run(["-h"]) }
      expect(output).to include("Usage: agentf update")
    end
  end

  describe "when stamp is missing (fresh install)" do
    it "runs installer and writes stamp" do
      FileUtils.mkdir_p(stamp_dir)

      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{root}",
          "--global-root=#{root}"
        ])
      end

      expect(output).to include("Installing v#{Agentf::VERSION}")
      expect(output).to include("CREATED")
      expect(output).to include("Stamp: #{Agentf::VERSION}")
      expect(File.read(stamp_path).strip).to eq(Agentf::VERSION)
      expect(installer_instances.size).to eq(1)
      expect(installer_instances.first.install_calls.size).to eq(1)
    end
  end

  describe "when stamp matches current version" do
    before do
      FileUtils.mkdir_p(stamp_dir)
      File.write(stamp_path, "#{Agentf::VERSION}\n")
    end

    it "skips update and reports up to date" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{root}",
          "--global-root=#{root}"
        ])
      end

      expect(output).to include("up to date")
      expect(output).to include("Already up to date.")
      expect(installer_instances).to be_empty
    end
  end

  describe "when stamp has older version" do
    before do
      FileUtils.mkdir_p(stamp_dir)
      File.write(stamp_path, "0.1.0\n")
    end

    it "runs installer and updates stamp" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{root}",
          "--global-root=#{root}"
        ])
      end

      expect(output).to include("Updating 0.1.0 -> #{Agentf::VERSION}")
      expect(output).to include("CREATED")
      expect(File.read(stamp_path).strip).to eq(Agentf::VERSION)
    end
  end

  describe "--force flag" do
    before do
      FileUtils.mkdir_p(stamp_dir)
      File.write(stamp_path, "#{Agentf::VERSION}\n")
    end

    it "regenerates even when version matches" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{root}",
          "--global-root=#{root}",
          "--force"
        ])
      end

      expect(output).to include("Force reinstalling v#{Agentf::VERSION}")
      expect(output).to include("CREATED")
      expect(installer_instances.size).to eq(1)
    end
  end

  describe "multiple providers" do
    let(:copilot_stamp_dir) { File.join(root, ".github") }
    let(:copilot_stamp_path) { File.join(copilot_stamp_dir, ".agentf-version") }

    it "checks and updates each provider independently" do
      FileUtils.mkdir_p(stamp_dir)
      FileUtils.mkdir_p(copilot_stamp_dir)

      # opencode is current, copilot has old version
      File.write(stamp_path, "#{Agentf::VERSION}\n")
      File.write(copilot_stamp_path, "0.1.0\n")

      output = capture_stdout do
        cli.run([
          "--provider=opencode,copilot",
          "--scope=local",
          "--local-root=#{root}",
          "--global-root=#{root}"
        ])
      end

      expect(output).to include("opencode")
      expect(output).to include("up to date")
      expect(output).to include("copilot")
      expect(output).to include("Updating 0.1.0 -> #{Agentf::VERSION}")

      # Only copilot stamp should have been rewritten
      expect(File.read(copilot_stamp_path).strip).to eq(Agentf::VERSION)
    end

    it "writes separate stamp files per provider" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode,copilot",
          "--scope=local",
          "--local-root=#{root}",
          "--global-root=#{root}"
        ])
      end

      expect(File.read(stamp_path).strip).to eq(Agentf::VERSION)
      expect(File.read(copilot_stamp_path).strip).to eq(Agentf::VERSION)
    end
  end

  describe "scope filtering" do
    let(:global_root) { Dir.mktmpdir("agentf-global") }
    let(:local_root) { Dir.mktmpdir("agentf-local") }

    after do
      FileUtils.remove_entry(global_root) if File.directory?(global_root)
      FileUtils.remove_entry(local_root) if File.directory?(local_root)
    end

    it "scope=local only checks local root" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=local",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}"
        ])
      end

      local_stamp = File.join(local_root, ".opencode", ".agentf-version")
      global_stamp = File.join(global_root, ".opencode", ".agentf-version")

      expect(File).to exist(local_stamp)
      expect(File).not_to exist(global_stamp)
    end

    it "scope=global only checks global root" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=global",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}"
        ])
      end

      local_stamp = File.join(local_root, ".opencode", ".agentf-version")
      global_stamp = File.join(global_root, ".opencode", ".agentf-version")

      expect(File).not_to exist(local_stamp)
      expect(File).to exist(global_stamp)
    end

    it "scope=all checks both roots" do
      output = capture_stdout do
        cli.run([
          "--provider=opencode",
          "--scope=all",
          "--local-root=#{local_root}",
          "--global-root=#{global_root}"
        ])
      end

      local_stamp = File.join(local_root, ".opencode", ".agentf-version")
      global_stamp = File.join(global_root, ".opencode", ".agentf-version")

      expect(File).to exist(local_stamp)
      expect(File).to exist(global_stamp)
    end
  end

  describe "unknown provider" do
    it "prints error to stderr" do
      output = nil
      stderr_output = nil

      original_stderr = $stderr
      stderr_io = StringIO.new
      $stderr = stderr_io

      begin
        output = capture_stdout do
          cli.run([
            "--provider=invalid",
            "--scope=local",
            "--local-root=#{root}",
            "--global-root=#{root}"
          ])
        end
      ensure
        $stderr = original_stderr
      end

      stderr_output = stderr_io.string
      expect(stderr_output).to include("Unknown provider: invalid")
      expect(output).to include("Already up to date.")
    end
  end

  describe "router integration" do
    it "dispatches 'update help' to Update CLI" do
      router = Agentf::CLI::Router.new
      expect { router.run(["update", "help"]) }
        .to output(include("Usage: agentf update"))
        .to_stdout
    end

    it "includes update in router help text" do
      router = Agentf::CLI::Router.new
      expect { router.run(["help"]) }
        .to output(include("update"))
        .to_stdout
    end
  end
end
