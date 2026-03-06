#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "agentf"

options = {
  providers: ["opencode"],
  scope: "all",
  global_root: Dir.home,
  local_root: Dir.pwd,
  dry_run: false,
  only_agents: nil,
  only_commands: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby bin/install.rb [options]"

  opts.on("-p", "--provider LIST", "Providers (comma-separated): opencode,copilot") do |value|
    providers = value.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
    options[:providers] = providers == ["all"] ? Agentf::Installer::PROVIDER_LAYOUTS.keys : providers
  end

  opts.on("-s", "--scope SCOPE", "Install scope: global|local|all (default: all)") do |value|
    options[:scope] = value.downcase
  end

  opts.on("--global-root PATH", "Root directory used for global installs (default: $HOME)") do |value|
    options[:global_root] = File.expand_path(value)
  end

  opts.on("--local-root PATH", "Root directory used for local installs (default: current directory)") do |value|
    options[:local_root] = File.expand_path(value)
  end

  opts.on("--agent LIST", "Only install specific agents (comma-separated names)") do |value|
    options[:only_agents] = value.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
  end

  opts.on("--command LIST", "Only install specific commands (comma-separated names)") do |value|
    options[:only_commands] = value.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
  end

  opts.on("--dry-run", "Show planned writes without writing files") do
    options[:dry_run] = true
  end

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit 0
  end
end

parser.parse!(ARGV)

installer = Agentf::Installer.new(
  global_root: options[:global_root],
  local_root: options[:local_root],
  dry_run: options[:dry_run]
)

results = installer.install(
  providers: options[:providers],
  scope: options[:scope],
  only_agents: options[:only_agents],
  only_commands: options[:only_commands]
)

results.each do |result|
  puts "#{result.fetch('status').upcase}: #{Pathname.new(result.fetch('path')).cleanpath}"
end

puts "\nCompleted #{results.size} manifest operations."
