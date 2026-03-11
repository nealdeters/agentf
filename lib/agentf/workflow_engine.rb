# frozen_string_literal: true

require_relative "agents"
require_relative "commands"
require_relative "context_builder"
require_relative "workflow_contract"
require_relative "agent_policy"

module Agentf
  class WorkflowEngine
    # Profiles previously lived in Agentf::Packs. They are now embedded in the
    # orchestrator so there's a single source of truth for workflow templates
    # and keyword-based inference used by both runtime orchestration and any
    # installer/CLI functionality.
    PROFILES = {
      "generic" => {
        "name" => "Generic",
        "description" => "Default provider workflows without domain specialization.",
        "keywords" => [],
        "workflow_templates" => {}
      },
      "rails_standard" => {
        "name" => "Rails Standard",
        "description" => "Thin models/controllers with services, queries, presenters, and policy reviews.",
        "keywords" => %w[rails activerecord rspec pundit viewcomponent hotwire turbo stimulus],
        "workflow_templates" => {
          "feature" => %w[PLANNER RESEARCHER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER KNOWLEDGE_MANAGER],
          "bugfix" => %w[PLANNER INCIDENT_RESPONDER ENGINEER QA_TESTER SECURITY_REVIEWER REVIEWER],
          "refactor" => %w[PLANNER RESEARCHER ENGINEER QA_TESTER REVIEWER],
          "quick_fix" => %w[ENGINEER QA_TESTER REVIEWER],
          "exploration" => %w[RESEARCHER]
        }
      },
      "rails_37signals" => {
        "name" => "Rails 37signals",
        "description" => "Resource-centric workflows favoring concerns, CRUD and model-rich patterns.",
        "keywords" => %w[rails concern crud closure model minitest hotwire],
        "workflow_templates" => {
          "feature" => %w[PLANNER RESEARCHER ENGINEER QA_TESTER REVIEWER KNOWLEDGE_MANAGER],
          "bugfix" => %w[PLANNER INCIDENT_RESPONDER ENGINEER QA_TESTER REVIEWER],
          "refactor" => %w[PLANNER ENGINEER QA_TESTER REVIEWER],
          "quick_fix" => %w[ENGINEER REVIEWER],
          "exploration" => %w[RESEARCHER]
        }
      },
      "rails_feature_spec" => {
        "name" => "Rails Feature Spec",
        "description" => "Feature-spec-first orchestration with planning and review emphasis.",
        "keywords" => %w[rails feature specification acceptance criteria],
        "workflow_templates" => {
          "feature" => %w[PLANNER RESEARCHER UI_ENGINEER ENGINEER QA_TESTER REVIEWER KNOWLEDGE_MANAGER],
          "bugfix" => %w[PLANNER INCIDENT_RESPONDER ENGINEER QA_TESTER REVIEWER],
          "refactor" => %w[PLANNER RESEARCHER ENGINEER QA_TESTER REVIEWER],
          "quick_fix" => %w[ENGINEER REVIEWER],
          "exploration" => %w[RESEARCHER]
        }
      }
    }.freeze
    PROVIDERS = {
      opencode: Agentf::Service::Providers::OpenCode,
      copilot: Agentf::Service::Providers::Copilot
    }.freeze

    attr_reader :memory, :base_path, :provider

    def initialize(memory: nil, base_path: nil, provider: :opencode)
      @memory = memory || Agentf::Memory::RedisMemory.new
      @base_path = base_path || Agentf.config.base_path
      @name = Agentf::AgentRoles::ORCHESTRATOR
      @provider_ref = provider
      # Initialize provider using the orchestrator's default profile ("generic").
      @provider = build_provider(@provider_ref, pack: "generic")

      @explorer_commands = Commands::Explorer.new(base_path: @base_path)
      @tester_commands = Commands::Tester.new(base_path: @base_path)
      @debugger_commands = Commands::Debugger.new(base_path: @base_path)
      @designer_commands = Commands::Designer.new(base_path: @base_path)
      @security_commands = Commands::SecurityScanner.new
      @architecture_commands = Commands::Architecture.new(base_path: @base_path)
      @metrics_commands = Agentf.config.metrics_enabled ? Commands::Metrics.new(memory: @memory) : nil
      @context_builder = ContextBuilder.new(memory: @memory)
      @agent_policy = Agentf::AgentPolicy.new
      @workflow_contract = Agentf::WorkflowContract.new(
        enabled: Agentf.config.workflow_contract_enabled,
        mode: Agentf.config.workflow_contract_mode
      )

      @agents = {
        Agentf::AgentRoles::PLANNER => Agents::Architect.new(@memory),
        Agentf::AgentRoles::ENGINEER => Agents::Specialist.new(@memory),
        Agentf::AgentRoles::REVIEWER => Agents::Reviewer.new(@memory),
        Agentf::AgentRoles::KNOWLEDGE_MANAGER => Agents::Documenter.new(@memory),
        Agentf::AgentRoles::RESEARCHER => Agents::Explorer.new(@memory, commands: @explorer_commands),
        Agentf::AgentRoles::QA_TESTER => Agents::Tester.new(@memory, commands: @tester_commands),
        Agentf::AgentRoles::INCIDENT_RESPONDER => Agents::Debugger.new(@memory, commands: @debugger_commands),
        Agentf::AgentRoles::UI_ENGINEER => Agents::Designer.new(@memory, commands: @designer_commands),
        Agentf::AgentRoles::SECURITY_REVIEWER => Agents::Security.new(@memory, commands: @security_commands)
      }

      @workflow_state = {}
    end

    def execute(task, context: nil)
      log "=" * 60
      log "EXECUTING #{provider.name} WORKFLOW"
      log "=" * 60

      resolved_context = context || {}
      selected_pack = resolve_pack(task: task, context: resolved_context)
      @provider = build_provider(@provider_ref, pack: selected_pack)

      @workflow_state = {
        "task" => task,
        "provider" => @provider.name,
        "pack" => selected_pack,
        "workflow_contract" => {
          "enabled" => @workflow_contract.enabled?,
          "mode" => @workflow_contract.mode,
          "events" => [],
          "blocked" => false
        },
        "context" => resolved_context,
        "results" => [],
        "completed_agents" => []
      }

      return @workflow_state if run_contract_stage("spec").fetch("blocked")

      plan = provider.build_plan(task: task, context: resolved_context, logger: method(:log))
      return @workflow_state if run_contract_stage("plan", plan: plan).fetch("blocked")

      @workflow_state.merge!(
        "provider" => plan["provider"],
        "workflow_type" => plan["workflow_type"],
        "tdd" => initialize_tdd_state(plan["workflow_type"]),
        "plan" => plan
      )

      attach_initial_brain_context
      persist_feature_intent(task: task, workflow_type: plan["workflow_type"], context: @workflow_state["context"])

      plan["agents_needed"].each do |agent_name|
        run_pre_specialist_tdd_cycle if agent_name == Agentf::AgentRoles::ENGINEER
        agent_result = execute_agent(agent_name)
        @workflow_state["results"] << { "agent" => agent_name, "result" => agent_result }
        @workflow_state["completed_agents"] << agent_name
      end

      return @workflow_state if run_contract_stage("execute").fetch("blocked")

      architecture_review = perform_architecture_review
      @workflow_state["architecture_review"] = architecture_review

      return @workflow_state if run_contract_stage("review").fetch("blocked")

      run_contract_stage("finalize")
      summary = summarize_workflow
      @workflow_state["summary"] = summary
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

    def build_provider(provider, pack:)
      return provider if provider.respond_to?(:build_plan)

      klass = PROVIDERS[provider.to_sym]
      raise ArgumentError, "Unknown provider: #{provider}. Valid providers: #{PROVIDERS.keys.join(', ')}" unless klass

      klass.new(pack: pack)
    end

    def resolve_pack(task:, context:)
      requested = context["pack"].to_s.strip
      return requested.downcase unless requested.empty?

      # No config-based default profile is kept; rely on orchestrator inference.
      infer_profile(context.merge("task" => task))
    end

    def infer_profile(context = {})
      text = [context["task"], context["design_spec"], context["stack"], context["framework"]]
             .compact.join(" ").downcase
      return "generic" if text.empty?

      return "rails_standard" if includes_any_keyword?(text, PROFILES["rails_standard"]["keywords"])

      "generic"
    end

    def includes_any_keyword?(text, keywords)
      keywords.any? { |keyword| text.include?(keyword) }
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

      if agent_name == Agentf::AgentRoles::QA_TESTER
        enriched_context["tdd_phase"] = @workflow_state.dig("tdd", "phase")
        enriched_context["tdd_failure_signature"] = @workflow_state.dig("tdd", "failure_signature")
      end

      if agent_name == Agentf::AgentRoles::ENGINEER
        enriched_context["tdd_phase"] = "green"
        enriched_context["expected_test_fix"] = @workflow_state.dig("tdd", "failure_signature")
      end

      if agent_name == Agentf::AgentRoles::REVIEWER
        enriched_context["execution"] = @workflow_state["results"].last&.fetch("result", {}) || {}
      end

      begin
        result = @provider.execute_agent(
          agent_name: agent_name,
          task: @workflow_state["task"],
          context: enriched_context,
          agents: @agents,
          commands: command_registry,
          logger: method(:log)
        )
      rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
        # An agent attempted to persist memory but policy requires confirmation.
        # Record the event and return a structured result that signals the
        # orchestrator/UI to prompt the user. Do NOT set an "error" key so
        # agent execution contract does not treat this as a failure.
        handle_memory_confirmation(e, attempted: { action: "agent_persist", agent: agent_name })
        return { "success" => false, "confirmation_required" => true, "confirmation_details" => e.details }
      end

      policy_violations = @agent_policy.validate(
        agent_name: agent_name,
        boundaries: @agents.fetch(agent_name).class.policy_boundaries,
        context: enriched_context,
        result: result,
        phase: :after
      )
      append_policy_violations(policy_violations)

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
        "security" => @security_commands,
        "architecture" => @architecture_commands
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
    rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
      handle_memory_confirmation(e, attempted: { action: "store_feature_intent", title: task, tags: tags })
    rescue StandardError => e
      log "Intent capture skipped: #{e.message}"
    end

    def persist_agent_learning(agent_name:, result:)
      return unless result.is_a?(Hash)

      if result["error"]
        begin
          @memory.store_pitfall(
            title: "#{agent_name} execution failure",
            description: result["error"],
            context: @workflow_state["task"],
            tags: [@workflow_state["workflow_type"], "workflow_error"],
            agent: agent_name,
            code_snippet: ""
          )
        rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
          handle_memory_confirmation(e, attempted: { action: "store_pitfall", agent: agent_name, error: result["error"] })
        end
        return
      end

      if agent_name == Agentf::AgentRoles::QA_TESTER && result["tdd_phase"] == "red" && result["passed"] == false
        begin
          @memory.store_pitfall(
            title: "TDD red phase captured",
            description: result["failure_signature"] || "Intentional failing test captured",
            context: @workflow_state["task"],
            tags: [@workflow_state["workflow_type"], "tdd_red"],
            agent: agent_name,
            code_snippet: ""
          )
        rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
          handle_memory_confirmation(e, attempted: { action: "store_pitfall", agent: agent_name, tdd: true })
        end
        return
      end

      if agent_name == Agentf::AgentRoles::QA_TESTER && result["tdd_phase"] == "green" && result["passed"] == true
        begin
          @memory.store_success(
            title: "TDD green phase passed",
            description: "Resolved failing test signature: #{result['failure_signature']}",
            context: @workflow_state["task"],
            tags: [@workflow_state["workflow_type"], "tdd_green"],
            agent: agent_name,
            code_snippet: ""
          )
        rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
          handle_memory_confirmation(e, attempted: { action: "store_success", agent: agent_name, tdd: true })
        end
        return
      end

      begin
        @memory.store_lesson(
          title: "#{agent_name} completed workflow step",
          description: "Agent step completed for #{@workflow_state['workflow_type']} workflow",
          context: @workflow_state["task"],
          tags: [@workflow_state["workflow_type"], "workflow_step"],
          agent: agent_name,
          code_snippet: ""
        )
      rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
        handle_memory_confirmation(e, attempted: { action: "store_lesson", agent: agent_name })
      end
    rescue StandardError => e
      log "Learning persistence skipped: #{e.message}"
    end

    def summarize_workflow
      results = @workflow_state["results"]
      errors = results.select { |r| r["result"]["error"] }
      reviews = results.select { |r| r["agent"] == Agentf::AgentRoles::REVIEWER }
      approved = reviews.any? { |r| r["result"]["approved"] }
      contract_blocked = @workflow_state.dig("workflow_contract", "blocked") == true

      {
        "status" => contract_blocked ? "blocked" : (errors.any? ? "failed" : (approved ? "approved" : "completed")),
        "total_agents" => results.size,
        "errors" => errors.size,
        "approved" => approved,
        "tdd" => @workflow_state["tdd"],
        "contract_blocked" => contract_blocked
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
        "brain" => @context_builder.build(agent: Agentf::AgentRoles::QA_TESTER, workflow_state: @workflow_state, limit: 8)
      )

      red_result = @provider.execute_agent(
        agent_name: Agentf::AgentRoles::QA_TESTER,
        task: @workflow_state["task"],
        context: red_context,
        agents: @agents,
        commands: command_registry,
        logger: method(:log)
      )

      tdd["red_executed"] = true
      tdd["failure_signature"] = red_result["failure_signature"]
      @workflow_state["results"] << { "agent" => "QA_TESTER_TDD_RED", "result" => red_result }
      persist_agent_learning(agent_name: Agentf::AgentRoles::QA_TESTER, result: red_result)
    rescue StandardError => e
      log "TDD red phase skipped: #{e.message}"
    end

    def transition_tdd_phase(agent_name:, result:)
      tdd = @workflow_state["tdd"]
      return unless tdd["enabled"]

      if agent_name == Agentf::AgentRoles::ENGINEER
        tdd["phase"] = "green"
      elsif agent_name == Agentf::AgentRoles::QA_TESTER && tdd["phase"] == "green"
        tdd["green_executed"] = true
      end

      return unless agent_name == Agentf::AgentRoles::QA_TESTER && result["tdd_phase"] == "green"

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

    def perform_architecture_review
      result = @architecture_commands.review_layer_violations
      begin
        @memory.store_lesson(
          title: "Architecture review completed",
          description: "Layer violations: #{Array(result['violations']).length}",
          context: @workflow_state["task"],
          tags: [@workflow_state["workflow_type"], "architecture_review"],
          agent: @name
        )
      rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
        handle_memory_confirmation(e, attempted: { action: "store_lesson", agent: @name, context: @workflow_state["task"] })
      end
      result
    rescue StandardError => e
      { "error" => e.message, "violations" => [] }
    end

    def run_contract_stage(stage, plan: nil)
      evaluation = @workflow_contract.check(stage: stage, workflow_state: @workflow_state, plan: plan)
      @workflow_state["workflow_contract"]["events"] << evaluation
      persist_contract_event(evaluation)

      if evaluation["blocked"]
        @workflow_state["workflow_contract"]["blocked"] = true
        log "Workflow blocked by contract at #{stage}: #{evaluation['violations'].map { |v| v['code'] }.join(', ')}"
      elsif evaluation["violations"].any?
        log "Workflow contract warnings at #{stage}: #{evaluation['violations'].map { |v| v['code'] }.join(', ')}"
      end

      evaluation
    end

    def persist_contract_event(evaluation)
      @memory.store_episode(
        type: "lesson",
        title: "Workflow contract #{evaluation['stage']} #{evaluation['ok'] ? 'passed' : 'violated'}",
        description: "mode=#{evaluation['mode']} blocked=#{evaluation['blocked']}",
        context: JSON.generate(evaluation),
        tags: ["workflow_contract", evaluation["stage"], evaluation["ok"] ? "pass" : "violation"],
        agent: @name,
        metadata: { "workflow_contract_event" => true }
      )
    rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
      handle_memory_confirmation(e, attempted: { action: "store_episode", title: "Workflow contract #{evaluation['stage']}", agent: @name })
    rescue StandardError => e
      log "Contract event persistence skipped: #{e.message}"
    end

    def append_policy_violations(policy_violations)
      return if policy_violations.empty?

      @workflow_state["policy_violations"] ||= []
      @workflow_state["policy_violations"].concat(policy_violations)
      policy_violations.each do |violation|
        begin
          @memory.store_episode(
            type: "pitfall",
            title: "Agent policy violation: #{violation['code']}",
            description: violation["message"],
            context: @workflow_state["task"],
            tags: ["agent_policy", violation["agent"].to_s.downcase],
            agent: @name,
            metadata: { "policy_violation" => true, "severity" => violation["severity"] }
          )
        rescue Agentf::Memory::RedisMemory::ConfirmationRequired => e
          handle_memory_confirmation(e, attempted: { action: "store_policy_violation", violation: violation, agent: @name })
        end
      end
    rescue StandardError => e
      log "Policy violation persistence skipped: #{e.message}"
    end

    # Handle a memory confirmation exception by recording an event in the
    # workflow_state and emitting a log. This allows the orchestrator or UI to
    # surface a prompt to the user, and optionally retry the attempted action
    # with explicit confirmation.
    def handle_memory_confirmation(exception, attempted: {})
      @workflow_state["memory_confirmation_required"] ||= []
      entry = {
        "timestamp" => Time.now.to_i,
        "confirmation_required" => true,
        "confirmation_details" => exception.details,
        "attempted" => attempted
      }
      @workflow_state["memory_confirmation_required"] << entry
      log "Memory confirmation required: #{exception.message} -- attempted=#{attempted.inspect}"
    end
  end
end
