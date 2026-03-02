# frozen_string_literal: true

# Load data classes
require_relative "tools/file_match"
require_relative "tools/test_template"
require_relative "tools/error_analysis"
require_relative "tools/component_spec"
require_relative "tools/security_scanner"

# Load tools
require_relative "tools/explorer"
require_relative "tools/tester"
require_relative "tools/debugger"
require_relative "tools/designer"
require_relative "tools/memory_reviewer"

module Agentf
  module Tools
    # All tools are loaded above
  end
end
