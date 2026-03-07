# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Agentf::CLI::Architecture do
  let(:architecture) { instance_double(Agentf::Commands::Architecture) }
  subject(:cli) { described_class.new(architecture: architecture) }

  it "prints analyze output" do
    allow(architecture).to receive(:analyze_layers).and_return("layers" => { "models" => 1 })
    expect { cli.run(["analyze"]) }.to output(include("models")).to_stdout
  end

  it "prints review output" do
    allow(architecture).to receive(:review_layer_violations).with(limit: 10).and_return("count" => 0, "violations" => [])
    expect { cli.run(["review"]) }.to output(include("violations")).to_stdout
  end

  it "returns json when requested" do
    allow(architecture).to receive(:analyze_layers).and_return("layers" => { "models" => 1 })
    output = capture_stdout { cli.run(["analyze", "--json"]) }
    payload = JSON.parse(output)
    expect(payload["layers"]).to have_key("models")
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
