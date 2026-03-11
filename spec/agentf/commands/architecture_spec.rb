# frozen_string_literal: true

RSpec.describe Agentf::Commands::Architecture do
  let(:base_path) { File.expand_path("../../fixtures", __dir__) }
  subject(:architecture) { described_class.new(base_path: base_path) }

  describe ".manifest" do
    it "exposes architecture command metadata"  , :aggregate_failures do
      manifest = described_class.manifest
      expect(manifest["name"]).to eq("architecture")
      names = manifest["commands"].map { |cmd| cmd["name"] }
      expect(names).to include("analyze_layers", "review_layer_violations", "plan_gradual_adoption")
    end
  end

  describe "#analyze_layers" do
    it "returns layer summary"  , :aggregate_failures do
      result = architecture.analyze_layers
      expect(result).to have_key("layers")
      expect(result).to have_key("layer_balance_score")
    end
  end

  describe "#plan_gradual_adoption" do
    it "returns ordered rollout steps"  , :aggregate_failures do
      result = architecture.plan_gradual_adoption(goal: "adopt layered rails")
      expect(result["goal"]).to eq("adopt layered rails")
      expect(result["steps"]).not_to be_empty
    end
  end
end
