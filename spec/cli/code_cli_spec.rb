# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"

RSpec.describe Agentf::CLI::Code do
  let(:explorer) { instance_double(Agentf::Commands::Explorer) }

  subject(:cli) { described_class.new(explorer: explorer) }

  describe "glob command" do
    it "returns JSON payload" do
      allow(explorer).to receive(:glob).with("app/**/*.rb", file_types: nil).and_return(
        ["app/models/user.rb", "app/controllers/api.rb"]
      )

      output = capture_stdout { cli.run(["glob", "app/**/*.rb", "--json"]) }

      payload = JSON.parse(output)
      expect(payload["command"]).to eq("glob")
      expect(payload["count"]).to eq(2)
      expect(payload["matches"]).to eq(["app/models/user.rb", "app/controllers/api.rb"])
    end

    it "shows human-readable output with file list (finding #13 fix)" do
      allow(explorer).to receive(:glob).with("lib/**/*.rb", file_types: nil).and_return(
        ["lib/agentf.rb", "lib/agentf/memory.rb"]
      )

      expect { cli.run(["glob", "lib/**/*.rb"]) }
        .to output(include("glob -> 2 results").and(include("lib/agentf.rb")))
        .to_stdout
    end

    it "errors on missing pattern" do
      expect { cli.run(["glob", "--json"]) }.to raise_error(SystemExit)
    end
  end

  describe "grep command" do
    it "returns JSON payload with matches" do
      match = { "path" => "lib/agentf.rb", "line_number" => 10, "content" => "class WorkflowEngine" }
      allow(explorer).to receive(:grep).with("WorkflowEngine", file_pattern: "*.rb", context_lines: 2)
        .and_return([match])

      output = capture_stdout { cli.run(["grep", "WorkflowEngine", "--file-pattern=*.rb", "--json"]) }

      payload = JSON.parse(output)
      expect(payload["command"]).to eq("grep")
      expect(payload["matches"]).to eq([match])
    end

    it "shows human-readable output with match details" do
      match = { "path" => "lib/agentf.rb", "line_number" => 10, "content" => "class WorkflowEngine" }
      allow(explorer).to receive(:grep).with("WorkflowEngine", file_pattern: nil, context_lines: 2)
        .and_return([match])

      expect { cli.run(["grep", "WorkflowEngine"]) }
        .to output(include("grep -> 1 results").and(include("lib/agentf.rb:10")))
        .to_stdout
    end
  end

  describe "tree command" do
    it "returns JSON payload" do
      tree = { "lib" => { "agentf.rb" => nil } }
      allow(explorer).to receive(:get_file_tree).with(max_depth: 3).and_return(tree)

      output = capture_stdout { cli.run(["tree", "--json"]) }

      payload = JSON.parse(output)
      expect(payload["command"]).to eq("tree")
      expect(payload["tree"]).to eq(tree)
    end

    it "shows human-readable tree output" do
      tree = { "lib" => { "agentf.rb" => nil }, "spec" => {} }
      allow(explorer).to receive(:get_file_tree).with(max_depth: 2).and_return(tree)

      expect { cli.run(["tree", "--depth=2"]) }
        .to output(include("tree -> 1 results").and(include("lib/")))
        .to_stdout
    end
  end

  describe "related command" do
    it "returns JSON payload with related file data" do
      related = { "imports" => ["lib/b.rb"], "tests" => ["spec/a_spec.rb"] }
      allow(explorer).to receive(:find_related_files).with("app/models/user.rb").and_return(related)

      output = capture_stdout { cli.run(["related", "app/models/user.rb", "--json"]) }

      payload = JSON.parse(output)
      expect(payload["command"]).to eq("related")
      expect(payload["target_file"]).to eq("app/models/user.rb")
      expect(payload["related"]["imports"]).to eq(["lib/b.rb"])
    end

    it "errors on missing target file" do
      expect { cli.run(["related", "--json"]) }.to raise_error(SystemExit)
    end
  end

  describe "help output" do
    it "includes usage info and examples" do
      output = capture_stdout { cli.run(["help"]) }

      aggregate_failures do
        expect(output).to include("related <file>")
        expect(output).to include("--json")
        expect(output).to include("agentf code glob")
      end
    end
  end

  describe "error handling" do
    it "exits on unknown subcommand" do
      expect { cli.run(["nonexistent"]) }.to raise_error(SystemExit)
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
