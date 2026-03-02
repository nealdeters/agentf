# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"
require "agentf"
require "fakeredis"

# Configure Agentf for testing
Agentf.configure do |config|
  config.redis_url = "redis://localhost:6379"
  config.project_name = "test-project"
  config.base_path = File.expand_path("fixtures", __dir__)
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = false
end
