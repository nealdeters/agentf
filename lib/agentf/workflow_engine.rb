# frozen_string_literal: true

require_relative "agents"
require_relative "commands"

module Agentf
  class WorkflowEngine
    PROVIDERS = {
      opencode: Agentf::Service::Providers::OpenCode,
      copilot: Agentf::Service::Providers::Copilot
    }.freeze

    attr_reader :memory, :base_path, :provider

    def initialize(memory: nil, base_path: nil, provider: :opencode)
      @memory = memory || Agentf::Memory::RedisMemory.new
      @base_path = base_path || Agentf.config.base_path
      @name = "WORKFLOW_ENGINE"
      @provider = build_provider(provider)

      @explorer_commands = Commands::Explorer.new(base_path: @base_path)
      @tester_commands = Commands::Tester.new(base_path: @base_path)
      @debugger_commands = Commands::Debugger.new(base_path: @base_path)
      @designer_commands = Commands::Designer.new(base_path: @base_path)
      @security_commands = Commands::SecurityScanner.new
      @metrics_commands = Agentf.config.metrics_enabled ? Commands::Metrics.new(memory: @memory) : nil

      @agents = {
        "ARCHITECT" => Agents::Architect.new(@memory),
        "SPECIALIST" => Agents::Specialist.new(@memory),
        "REVIEWER" => Agents::Reviewer.new(@memory),
        "DOCUMENTER" => Agents::Documenter.new(@memory),
        "EXPLORER" => Agents::Explorer.new(@memory, commands: @explorer_commands),
        "TESTER" => Agents::Tester.new(@memory, commands: @tester_commands),
        "DEBUGGER" => Agents::Debugger.new(@memory, commands: @debugger_commands),
        "DESIGNER" => Agents::Designer.new(@memory, commands: @designer_commands),
        "SECURITY" => Agents::Security.new(@memory, commands: @security_commands)
      }

      @workflow_state = {}
    end

    def execute(task, context: nil)
      log "=" * 60
      log "EXECUTING #{provider.name} WORKFLOW"
      log "=" * 60

      plan = provider.build_plan(task: task, context: context || {}, logger: method(:log))

      @workflow_state = {
        "task" => task,
        "provider" => plan["provider"],
        "workflow_type" => plan["workflow_type"],
        "context" => context || {},
        "results" => [],
        "completed_agents" => []
      }

      attach_initial_brain_context
      persist_feature_intent(task: task, workflow_type: plan["workflow_type"], context: @workflow_state["context"])

      plan["agents_needed"].each do |agent_name|
        agent_result = execute_agent(agent_name)
        @workflow_state["results"] << { "agent" => agent_name, "result" => agent_result }
        @workflow_state["completed_agents"] << agent_name
      end

      summary = summarize_workflow
      record_workflow_metrics

      log ""
      log "=" * 60
      log "WORKFLOW COMPLETE"
      log "=" * 60
      log "Provider: #{plan['provider']}"
      log "Workflow type: #{plan['workflow_type']}"
      log "Agents executed: #{@workflow_state['completed_agents'].size}"
      log "Overall status: #{summary['status']}"

      @workflow_state
    end

    private

    def build_provider(provider)
      return provider if provider.respond_to?(:build_plan)

      klass = PROVIDERS[provider.to_sym]
      raise ArgumentError, "Unknown provider: #{provider}. Valid providers: #{PROVIDERS.keys.join(', ')}" unless klass

      klass.new
    end

    def log(message)
      puts "\n[#{@name}] #{message}"
    end

    def execute_agent(agent_name)
      context = @workflow_state["context"]
      enriched_context = context.merge(
        "brain" => @memory.get_relevant_context(
          agent: agent_name,
          task_type: @workflow_state["workflow_type"],
          limit: 8
        )
      )

      result = @provider.execute_agent(
        agent_name: agent_name,
        task: @workflow_state["task"],
        context: enriched_context,
        agents: @agents,
        commands: command_registry,
        logger: method(:log)
      )

      persist_agent_learning(agent_name: agent_name, result: result)
      result
    end

    def command_registry
      {
        "explorer" => @explorer_commands,
        "tester" => @tester_commands,
        "debugger" => @debugger_commands,
        "designer" => @designer_commands,
        "security" => @security_commands
      }
    end

    def attach_initial_brain_context
      @workflow_state["context"]["brain"] = @memory.get_relevant_context(
        agent: @name,
        task_type: @workflow_state["workflow_type"],
        limit: 8
      )
    rescue StandardError
      @workflow_state["context"]["brain"] = {}
    end

    def persist_feature_intent(task:, workflow_type:, context:)
      acceptance_criteria = Array(context["acceptance_criteria"])
      non_goals = Array(context["non_goals"])
      tags = [workflow_type, @provider.name.downcase]

      @memory.store_feature_intent(
        title: task,
        description: "Workflow intent captured by workflow engine",
        acceptance_criteria: acceptance_criteria,
        non_goals: non_goals,
        tags: tags,
        agent: @name
      )
    rescue StandardError => e
      log "Intent capture skipped: #{e.message}"
    end

    def persist_agent_learning(agent_name:, result:)
      return unless result.is_a?(Hash)

      if result["error"]
        @memory.store_pitfall(
          title: "#{agent_name} execution failure",
          description: result["error"],
          context: @workflow_state["task"],
          tags: [@workflow_state["workflow_type"], "workflow_error"],
          agent: agent_name,
          code_snippet: ""
        )
        return
      end

      @memory.store_lesson(
        title: "#{agent_name} completed workflow step",
        description: "Agent step completed for #{@workflow_state['workflow_type']} workflow",
        context: @workflow_state["task"],
        tags: [@workflow_state["workflow_type"], "workflow_step"],
        agent: agent_name,
        code_snippet: ""
      )
    rescue StandardError => e
      log "Learning persistence skipped: #{e.message}"
    end

    def summarize_workflow
      results = @workflow_state["results"]
      errors = results.select { |r| r["result"]["error"] }
      reviews = results.select { |r| r["agent"] == "REVIEWER" }
      approved = reviews.any? { |r| r["result"]["approved"] }

      {
        "status" => errors.any? ? "failed" : (approved ? "approved" : "completed"),
        "total_agents" => results.size,
        "errors" => errors.size,
        "approved" => approved
      }
    end

    def record_workflow_metrics
      return unless @metrics_commands

      result = @metrics_commands.record_workflow(@workflow_state)
      return if result["status"] == "recorded"

      log "Metrics capture skipped: #{result['error']}"
    rescue StandardError => e
      log "Metrics capture skipped: #{e.message}"
    end
  end
end
