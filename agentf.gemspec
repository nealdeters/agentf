# frozen_string_literal: true

require_relative "lib/agentf/version"

Gem::Specification.new do |spec|
  spec.name          = "agentf"
  spec.version       = Agentf::VERSION
  spec.authors       = ["Neal Deters"]
  spec.summary       = "A self-learning swarm of agents with shared memory"
  spec.description   = <<-DESC
    A multi-agent system with Redis-backed memory for code execution,
    testing, debugging, and design implementation. Designed for
    frontend, backend, and API development workflows.
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
  spec.add_runtime_dependency "mcp-rb", "~> 0.3"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "fakeredis", ">= 0.9.0"
end
