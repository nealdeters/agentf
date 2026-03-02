# frozen_string_literal: true

# Load all agents
require_relative "agents/base"
require_relative "agents/architect"
require_relative "agents/specialist"
require_relative "agents/reviewer"
require_relative "agents/documenter"
require_relative "agents/explorer"
require_relative "agents/tester"
require_relative "agents/debugger"
require_relative "agents/designer"
require_relative "agents/security"

module Agentf
  module Agents
    # All agents are loaded above
  end
end
