# frozen_string_literal: true

require_relative "agents"
require_relative "tools"

module Agentf
  # Orchestrator - Central workflow coordinator
  class Orchestrator
    WORKFLOW_TEMPLATES = {
      "feature" => %w[ARCHITECT EXPLORER DESIGNER SPECIALIST TESTER SECURITY REVIEWER DOCUMENTER],
      "bugfix" => %w[ARCHITECT DEBUGGER SPECIALIST TESTER SECURITY REVIEWER],
      "quick_fix" => %w[SPECIALIST SECURITY REVIEWER],
      "exploration" => %w[EXPLORER],
      "refactor" => %w[ARCHITECT EXPLORER SPECIALIST TESTER SECURITY REVIEWER]
    }.freeze

    attr_reader :memory, :base_path

    def initialize(memory: nil, base_path: nil)
      @memory = memory || Agentf::Memory::RedisMemory.new
      @base_path = base_path || Agentf.config.base_path
      @name = "ORCHESTRATOR"

      # Initialize tools
      @explorer_tools = Tools::Explorer.new(base_path: @base_path)
      @tester_tools = Tools::Tester.new(base_path: @base_path)
      @debugger_tools = Tools::Debugger.new(base_path: @base_path)
      @designer_tools = Tools::Designer.new(base_path: @base_path)
      @security_tools = Tools::SecurityScanner.new

      # Initialize agents
      @agents = {
        "ARCHITECT" => Agents::Architect.new(@memory),
        "SPECIALIST" => Agents::Specialist.new(@memory),
        "REVIEWER" => Agents::Reviewer.new(@memory),
        "DOCUMENTER" => Agents::Documenter.new(@memory),
        "EXPLORER" => Agents::Explorer.new(@memory, tools: @explorer_tools),
        "TESTER" => Agents::Tester.new(@memory, tools: @tester_tools),
        "DEBUGGER" => Agents::Debugger.new(@memory, tools: @debugger_tools),
        "DESIGNER" => Agents::Designer.new(@memory, tools: @designer_tools),
        "SECURITY" => Agents::Security.new(@memory, tools: @security_tools)
      }

      @workflow_state = {}
    end

    def analyze_task(task)
      log "Analyzing task: #{task}"

      task_lower = task.downcase

      workflow_type = case
                      when task_lower =~ /quick|small|simple/ then "quick_fix"
                      when task_lower =~ /fix|bug|error|issue|broken/ then "bugfix"
                      when task_lower =~ /explore|find|search|where/ then "exploration"
                      when task_lower =~ /refactor|improve|cleanup/ then "refactor"
                      else
                        "feature"
                      end

      agents_needed = WORKFLOW_TEMPLATES[workflow_type]

      log "Workflow type: #{workflow_type}"
      log "Agents needed: #{agents_needed.join(', ')}"

      {
        "workflow_type" => workflow_type,
        "agents_needed" => agents_needed,
        "task" => task
      }
    end

    def execute_workflow(task, context: nil)
      log "=" * 60
      log "EXECUTING WORKFLOW"
      log "=" * 60

      # Analyze task
      analysis = analyze_task(task)
      workflow_type = analysis["workflow_type"]

      # Initialize state
      @workflow_state = {
        "task" => task,
        "workflow_type" => workflow_type,
        "context" => context || {},
        "results" => [],
        "completed_agents" => []
      }

      # Execute agents in sequence
      analysis["agents_needed"].each do |agent_name|
        agent_result = execute_agent(agent_name)
        @workflow_state["results"] << {
          "agent" => agent_name,
          "result" => agent_result
        }
        @workflow_state["completed_agents"] << agent_name
      end

      # Summarize results
      summary = summarize_workflow

      log ""
      log "=" * 60
      log "WORKFLOW COMPLETE"
      log "=" * 60
      log "Workflow type: #{workflow_type}"
      log "Agents executed: #{@workflow_state['completed_agents'].size}"
      log "Overall status: #{summary['status']}"

      @workflow_state
    end

    private

    def log(message)
      puts "\n[#{@name}] #{message}"
    end

    def execute_agent(agent_name)
      log "→ Calling #{agent_name}"

      agent = @agents[agent_name]
      return { "error" => "Agent #{agent_name} not found" } unless agent

      context = @workflow_state["context"]

      begin
        result = case agent_name
                 when "ARCHITECT"
                   agent.plan_task(@workflow_state["task"])
                 when "EXPLORER"
                   query = context["explore_query"] || "*.rb"
                   files = @explorer_tools.glob(query)
                   result = agent.explore(query)
                   result["files"] = files
                   result
                 when "TESTER"
                   source_file = context["source_file"] || "app/models/application_record.rb"
                   template = @tester_tools.generate_unit_tests(source_file)
                   result = agent.generate_tests(source_file)
                   result["generated_code"] = template.test_code
                   result
                 when "DEBUGGER"
                   error = context["error"] || "No error provided"
                   analysis = @debugger_tools.parse_error(error)
                   result = agent.diagnose(error, context: context["error_context"])
                   result["analysis"] = {
                     "error_type" => analysis.error_type,
                     "root_cause" => analysis.possible_causes,
                     "suggested_fix" => analysis.suggested_fix
                   }
                   result
                 when "DESIGNER"
                   design_spec = context["design_spec"] || "Create a card component"
                   spec = @designer_tools.generate_component("GeneratedComponent", design_spec)
                   result = agent.implement_design(design_spec)
                   result["generated_code"] = spec.code
                   result
                 when "SPECIALIST"
                   subtask = context["current_subtask"] || { "description" => @workflow_state["task"] }
                   agent.execute(subtask)
                  when "SECURITY"
                    agent.assess(task: @workflow_state["task"], context: context)
                  when "REVIEWER"
                   last_result = context["execution"] || {}
                   agent.review(last_result)
                 when "DOCUMENTER"
                   agent.sync_docs("project")
                 else
                   { "status" => "not_implemented" }
                 end

        log "→ #{agent_name} Complete"
        result
      rescue StandardError => e
        log "→ #{agent_name} Error: #{e.message}"
        { "error" => e.message, "agent" => agent_name }
      end
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
  end
end
