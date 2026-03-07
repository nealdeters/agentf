# frozen_string_literal: true

require_relative "agents"
require_relative "commands"
require_relative "context_builder"

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
      @context_builder = ContextBuilder.new(memory: @memory)

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
        "tdd" => initialize_tdd_state(plan["workflow_type"]),
        "results" => [],
        "completed_agents" => []
      }

      attach_initial_brain_context
      persist_feature_intent(task: task, workflow_type: plan["workflow_type"], context: @workflow_state["context"])

      plan["agents_needed"].each do |agent_name|
        run_pre_specialist_tdd_cycle if agent_name == "SPECIALIST"
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
        "brain" => @context_builder.build(
          agent: agent_name,
          workflow_state: @workflow_state,
          limit: 8
        )
      )

      if agent_name == "TESTER"
        enriched_context["tdd_phase"] = @workflow_state.dig("tdd", "phase")
        enriched_context["tdd_failure_signature"] = @workflow_state.dig("tdd", "failure_signature")
      end

      if agent_name == "SPECIALIST"
        enriched_context["tdd_phase"] = "green"
        enriched_context["expected_test_fix"] = @workflow_state.dig("tdd", "failure_signature")
      end

      result = @provider.execute_agent(
        agent_name: agent_name,
        task: @workflow_state["task"],
        context: enriched_context,
        agents: @agents,
        commands: command_registry,
        logger: method(:log)
      )

      persist_agent_learning(agent_name: agent_name, result: result)
      transition_tdd_phase(agent_name: agent_name, result: result)
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
      @workflow_state["context"]["brain"] = @context_builder.build(
        agent: @name,
        workflow_state: @workflow_state,
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

      if agent_name == "TESTER" && result["tdd_phase"] == "red" && result["passed"] == false
        @memory.store_pitfall(
          title: "TDD red phase captured",
          description: result["failure_signature"] || "Intentional failing test captured",
          context: @workflow_state["task"],
          tags: [@workflow_state["workflow_type"], "tdd_red"],
          agent: agent_name,
          code_snippet: ""
        )
        return
      end

      if agent_name == "TESTER" && result["tdd_phase"] == "green" && result["passed"] == true
        @memory.store_success(
          title: "TDD green phase passed",
          description: "Resolved failing test signature: #{result['failure_signature']}",
          context: @workflow_state["task"],
          tags: [@workflow_state["workflow_type"], "tdd_green"],
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
        "approved" => approved,
        "tdd" => @workflow_state["tdd"]
      }
    end

    def initialize_tdd_state(workflow_type)
      enabled = %w[feature bugfix refactor].include?(workflow_type)
      {
        "enabled" => enabled,
        "phase" => enabled ? "red" : "disabled",
        "failure_signature" => nil,
        "red_executed" => false,
        "green_executed" => false
      }
    end

    def run_pre_specialist_tdd_cycle
      tdd = @workflow_state["tdd"]
      return unless tdd["enabled"]
      return if tdd["red_executed"]

      red_context = @workflow_state["context"].merge(
        "tdd_phase" => "red",
        "brain" => @context_builder.build(agent: "TESTER", workflow_state: @workflow_state, limit: 8)
      )

      red_result = @provider.execute_agent(
        agent_name: "TESTER",
        task: @workflow_state["task"],
        context: red_context,
        agents: @agents,
        commands: command_registry,
        logger: method(:log)
      )

      tdd["red_executed"] = true
      tdd["failure_signature"] = red_result["failure_signature"]
      @workflow_state["results"] << { "agent" => "TESTER_TDD_RED", "result" => red_result }
      persist_agent_learning(agent_name: "TESTER", result: red_result)
    rescue StandardError => e
      log "TDD red phase skipped: #{e.message}"
    end

    def transition_tdd_phase(agent_name:, result:)
      tdd = @workflow_state["tdd"]
      return unless tdd["enabled"]

      if agent_name == "SPECIALIST"
        tdd["phase"] = "green"
      elsif agent_name == "TESTER" && tdd["phase"] == "green"
        tdd["green_executed"] = true
      end

      return unless agent_name == "TESTER" && result["tdd_phase"] == "green"

      tdd["failure_signature"] ||= result["failure_signature"]
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
