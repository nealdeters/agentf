# frozen_string_literal: true

require_relative "lib/agentf/version"

Gem::Specification.new do |spec|
  spec.name          = "agentf"
  spec.version       = Agentf::VERSION
  spec.authors       = ["Neal Deters"]
  spec.summary       = "Ruby multi-agent workflow engine with Redis memory"
  spec.description   = <<-DESC
    Agentf is a Ruby-native multi-agent workflow engine with an ORCHESTRATOR,
    role-specialized agents, provider adapters (OpenCode/Copilot), and
    Redis-backed semantic, episodic, and graph-style memory. It includes a
    unified CLI, MCP server tools, and install/update workflows for generated
    agent/command manifests.
  DESC
  spec.homepage      = "https://github.com/nealdeters/agentf"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nealdeters/agentf"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files         = Dir.glob("lib/**/*.rb") + Dir.glob("bin/*")
  spec.require_paths = ["lib"]

  spec.executables   = ["agentf"]

  spec.add_runtime_dependency "redis", "~> 4.8"
  spec.add_runtime_dependency "dotenv", "~> 2.8"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "fakeredis", ">= 0.9.0"
end
