# frozen_string_literal: true

RSpec.describe Agentf::Tools::ComponentSpec do
  subject(:component) do
    described_class.new(
      name: "Button",
      code: "<button>Click</button>",
      framework: "react",
      style: "css",
      props: [
        { "name" => "label", "type" => "string", "required" => true }
      ]
    )
  end

  it "exposes basic attributes"  , :aggregate_failures do
    expect(component.name).to eq("Button")
    expect(component.code).to include("<button>")
    expect(component.framework).to eq("react")
    expect(component.style).to eq("css")
    expect(component.props).to eq([
      { "name" => "label", "type" => "string", "required" => true }
    ])
  end

  describe "#to_h" do
    it "returns a hash representation" do
      expect(component.to_h).to eq(
        "name" => "Button",
        "code" => "<button>Click</button>",
        "framework" => "react",
        "style" => "css",
        "props" => [
          { "name" => "label", "type" => "string", "required" => true }
        ]
      )
    end
  end
end
