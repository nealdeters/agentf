# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "bundler/setup"
begin
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    coverage_dir "coverage"
  end
rescue LoadError
  # SimpleCov is optional in CI/local dev
end
require "agentf"
require "fakeredis"

# Load support helpers
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

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

  # Clear fakeredis between tests to prevent state leakage
  config.before(:each) do
    Redis.new(url: "redis://localhost:6379").flushall
  end

  # Provide a per-example test helper to auto-confirm memory writes when needed.
  # Use metadata `:auto_confirm_memory => true` on an example or describe block.
  config.around(:each) do |example|
    if example.metadata[:auto_confirm_memory]
      old = ENV['AGENTF_AUTO_CONFIRM_MEMORIES']
      ENV['AGENTF_AUTO_CONFIRM_MEMORIES'] = 'true'
      begin
        example.run
      ensure
        ENV['AGENTF_AUTO_CONFIRM_MEMORIES'] = old
      end
    else
      example.run
    end
  end

  # Default to aggregate failures for faster feedback across the suite.
  # This applies `:aggregate_failures` to all examples so multiple expectations
  # in a single example report together.
  config.define_derived_metadata do |meta|
    meta[:aggregate_failures] = true
  end
end
