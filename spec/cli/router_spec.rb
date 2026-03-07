# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Agentf::CLI::Router do
  subject(:router) { described_class.new }

  describe "version command" do
    %w[version --version -v].each do |flag|
      it "prints version for '#{flag}'" do
        expect { router.run([flag]) }
          .to output(include("agentf #{Agentf::VERSION}"))
          .to_stdout
      end
    end
  end

  describe "help command" do
    %w[help --help -h].each do |flag|
      it "prints help for '#{flag}'" do
        expect { router.run([flag]) }
          .to output(include("Usage: agentf <command>"))
          .to_stdout
      end
    end

    it "prints help when called with no arguments" do
      expect { router.run([]) }
        .to output(include("Usage: agentf <command>"))
        .to_stdout
    end
  end

  describe "unknown command" do
    it "prints error and exits" do
      expect { router.run(["nonexistent"]) }.to raise_error(SystemExit)
    end
  end

  describe "subcommand dispatch" do
    around do |example|
      original = Agentf.config.metrics_enabled
      Agentf.config.metrics_enabled = true
      example.run
    ensure
      Agentf.config.metrics_enabled = original
    end

    it "dispatches 'memory help' to Memory CLI" do
      expect { router.run(["memory", "help"]) }
        .to output(include("Usage: agentf memory"))
        .to_stdout
    end

    it "dispatches 'code help' to Code CLI" do
      expect { router.run(["code", "help"]) }
        .to output(include("Usage: agentf code"))
        .to_stdout
    end

    it "dispatches 'install help' to Install CLI" do
      expect { router.run(["install", "help"]) }
        .to output(include("Usage: agentf install"))
        .to_stdout
    end

    it "dispatches 'metrics help' to Metrics CLI" do
      expect { router.run(["metrics", "help"]) }
        .to output(include("Usage: agentf metrics"))
        .to_stdout
    end

    it "dispatches 'architecture help' to Architecture CLI" do
      expect { router.run(["architecture", "help"]) }
        .to output(include("Usage: agentf architecture"))
        .to_stdout
    end

    it "fails metrics command when metrics are disabled" do
      Agentf.config.metrics_enabled = false

      expect { router.run(["metrics", "summary"]) }
        .to raise_error(SystemExit)
    end
  end
end
