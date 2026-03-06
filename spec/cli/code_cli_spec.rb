# frozen_string_literal: true

require "spec_helper"
require "json"

load File.expand_path("../../bin/agentf-code", __dir__)

RSpec.describe Agentf::CodeCLI do
  describe "glob command" do
    it "returns JSON payload" do
      output = capture_stdout do
        described_class.new.run(["glob", "app/**/*.rb", "--json"])
      end

      payload = JSON.parse(output)
      expect(payload["command"]).to eq("glob")
      expect(payload["count"]).to be >= 1
      expect(payload["matches"]).to be_an(Array)
    end
  end

  describe "grep command" do
    it "returns JSON payload with matches" do
      output = capture_stdout do
        described_class.new.run(["grep", "WorkflowEngine", "--file-pattern=*.rb", "--json"])
      end

      payload = JSON.parse(output)
      expect(payload["command"]).to eq("grep")
      expect(payload["matches"]).to be_an(Array)
    end
  end

  describe "related command" do
    it "returns JSON payload with related file data" do
      output = capture_stdout do
        described_class.new.run(["related", "app/models/user.rb", "--json"])
      end

      payload = JSON.parse(output)
      expect(payload["command"]).to eq("related")
      expect(payload["target_file"]).to eq("app/models/user.rb")
      expect(payload["related"]).to be_a(Hash)
      expect(payload["related"]["imports"]).to be_an(Array)
    end
  end

  describe "help output" do
    it "includes JSON examples and related command" do
      output = capture_stdout do
        described_class.new.run(["help"])
      end

      aggregate_failures do
        expect(output).to include("related <file>")
        expect(output).to include("--json")
        expect(output).to include("ruby bin/agentf-code related")
      end
    end
  end

  describe "error handling" do
    it "returns JSON error for missing glob pattern" do
      expect do
        capture_stdout { described_class.new.run(["glob", "--json"]) }
      end.to raise_error(SystemExit)
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
