# frozen_string_literal: true

module Agentf
  module CLI
    # CLI subcommand for memory operations.
    # Refactored from bin/agentf-memory with bug fixes:
    #   - show_help now prints output (finding #6)
    #   - extract_limit removes consumed args (finding #8)
    #   - search_memories extracts limit before joining query (finding #7)
    #   - parse_single_option removes consumed args (finding #9)
    #   - @json_output is a proper boolean (finding #10)
    #   - by_type accepts business_intent and feature_intent (finding #11)
    class Memory
      include ArgParser

      VALID_EPISODE_TYPES = %w[pitfall lesson success business_intent feature_intent].freeze

      def initialize(reviewer: nil, memory: nil)
        @reviewer = reviewer || Commands::MemoryReviewer.new
        @memory = memory || Agentf::Memory::RedisMemory.new
        @json_output = false
      end

      def run(args)
        @json_output = !args.delete("--json").nil?
        command = args.shift || "help"

        case command
        when "recent", "list"
          list_memories(args)
        when "pitfalls"
          list_pitfalls(args)
        when "lessons"
          list_lessons(args)
        when "successes"
          list_successes(args)
        when "intents"
          list_intents(args)
        when "business-intents"
          list_business_intents(args)
        when "feature-intents"
          list_feature_intents(args)
        when "add-business-intent"
          add_business_intent(args)
        when "add-feature-intent"
          add_feature_intent(args)
        when "add-lesson"
          add_episode("lesson", args)
        when "add-success"
          add_episode("success", args)
        when "add-pitfall"
          add_episode("pitfall", args)
        when "tags"
          list_tags
        when "search"
          search_memories(args)
        when "delete"
          delete_memories(args)
        when "neighbors"
          neighbors(args)
        when "subgraph"
          subgraph(args)
        when "summary", "stats"
          show_summary
        when "by-tag"
          by_tag(args)
        when "by-agent"
          by_agent(args)
        when "by-type"
          by_type(args)
        when "help", "--help", "-h"
          show_help
        else
          $stderr.puts "Unknown memory command: #{command}"
          $stderr.puts
          show_help
          exit 1
        end
      end

      private

      def list_memories(args)
        limit = extract_limit(args)
        result = @reviewer.get_recent_memories(limit: limit)
        output(result)
      end

      def list_pitfalls(args)
        limit = extract_limit(args)
        result = @reviewer.get_pitfalls(limit: limit)
        output(result)
      end

      def list_lessons(args)
        limit = extract_limit(args)
        result = @reviewer.get_lessons(limit: limit)
        output(result)
      end

      def list_successes(args)
        limit = extract_limit(args)
        result = @reviewer.get_successes(limit: limit)
        output(result)
      end

      def list_intents(args)
        limit = extract_limit(args)
        kind = args.shift

        result = case kind
                 when "business"
                   @reviewer.get_business_intents(limit: limit)
                 when "feature"
                   @reviewer.get_feature_intents(limit: limit)
                 else
                   business = @reviewer.get_business_intents(limit: limit)
                   feature = @reviewer.get_feature_intents(limit: limit)
                   merge_memory_results(business, feature, limit: limit)
                 end

        output(result)
      end

      def list_business_intents(args)
        limit = extract_limit(args)
        output(@reviewer.get_business_intents(limit: limit))
      end

      def list_feature_intents(args)
        limit = extract_limit(args)
        output(@reviewer.get_feature_intents(limit: limit))
      end

      def add_business_intent(args)
        title = args.shift
        description = args.shift

        if title.to_s.empty? || description.to_s.empty?
          $stderr.puts "Error: add-business-intent requires <title> <description>"
          exit 1
        end

        tags = parse_list_option(args, "--tags=")
        constraints = parse_list_option(args, "--constraints=")
        priority = parse_integer_option(args, "--priority=", default: 1)

        intent_id = @memory.store_business_intent(
          title: title,
          description: description,
          tags: tags,
          constraints: constraints,
          priority: priority
        )

        if @json_output
          puts JSON.generate({ "id" => intent_id, "type" => "business_intent", "status" => "stored" })
        else
          puts "Stored business intent: #{intent_id}"
        end
      end

      def add_feature_intent(args)
        title = args.shift
        description = args.shift

        if title.to_s.empty? || description.to_s.empty?
          $stderr.puts "Error: add-feature-intent requires <title> <description>"
          exit 1
        end

        tags = parse_list_option(args, "--tags=")
        acceptance_criteria = parse_list_option(args, "--acceptance=")
        non_goals = parse_list_option(args, "--non-goals=")
        related_task_id = parse_single_option(args, "--task=")

        intent_id = @memory.store_feature_intent(
          title: title,
          description: description,
          tags: tags,
          acceptance_criteria: acceptance_criteria,
          non_goals: non_goals,
          related_task_id: related_task_id
        )

        if @json_output
          puts JSON.generate({ "id" => intent_id, "type" => "feature_intent", "status" => "stored" })
        else
          puts "Stored feature intent: #{intent_id}"
        end
      end

      def add_episode(type, args)
        title = args.shift
        description = args.shift

        if title.to_s.empty? || description.to_s.empty?
          $stderr.puts "Error: add-#{type} requires <title> <description>"
          exit 1
        end

        tags = parse_list_option(args, "--tags=")
        context = parse_single_option(args, "--context=").to_s
        agent = parse_single_option(args, "--agent=") || Agentf::AgentRoles::ENGINEER
        code_snippet = parse_single_option(args, "--code=").to_s

        intent_id = @memory.store_episode(
          type: type,
          title: title,
          description: description,
          context: context,
          tags: tags,
          agent: agent,
          code_snippet: code_snippet
        )

        if @json_output
          puts JSON.generate({ "id" => intent_id, "type" => type, "status" => "stored" })
        else
          puts "Stored #{type}: #{intent_id}"
        end
      end

      def list_tags
        result = @reviewer.get_all_tags
        if @json_output
          puts JSON.generate(result)
          return
        end

        if result["tags"].empty?
          puts "No tags found."
        else
          puts "Tags (#{result["count"]}):"
          result["tags"].each { |tag| puts "  - #{tag}" }
        end
      end

      def search_memories(args)
        # Extract limit BEFORE joining remaining args as query (fixes finding #7)
        limit = extract_limit(args)
        query = args.join(" ")

        if query.empty?
          $stderr.puts "Error: search requires a query string"
          exit 1
        end

        result = @reviewer.search(query, limit: limit)
        output(result)
      end

      def show_summary
        result = @reviewer.get_summary
        if @json_output
          puts JSON.generate(result)
          return
        end

        puts "Memory Summary for project: #{result["project"]}"
        puts "-" * 40
        puts "Total memories: #{result["total_memories"]}"
        puts ""
        puts "By type:"
        result["by_type"].each { |type, count| puts "  #{type}: #{count}" }
        puts ""
        puts "By agent:"
        result["by_agent"].each { |agent, count| puts "  #{agent}: #{count}" }
        puts ""
        puts "Unique tags: #{result["unique_tags"]}"
      end

      def by_tag(args)
        tag = args.shift
        if tag.nil? || tag.empty?
          $stderr.puts "Error: by-tag requires a tag name"
          exit 1
        end
        limit = extract_limit(args)
        result = @reviewer.get_by_tag(tag, limit: limit)
        output(result)
      end

      def by_agent(args)
        agent = args.shift
        if agent.nil? || agent.empty?
          $stderr.puts "Error: by-agent requires an agent name"
          exit 1
        end
        limit = extract_limit(args)
        result = @reviewer.get_by_agent(agent, limit: limit)
        output(result)
      end

      def by_type(args)
        type = args.shift
        unless VALID_EPISODE_TYPES.include?(type)
          $stderr.puts "Error: type must be one of: #{VALID_EPISODE_TYPES.join(", ")}"
          exit 1
        end
        limit = extract_limit(args)
        result = @reviewer.get_by_type(type, limit: limit)
        output(result)
      end

      def neighbors(args)
        node_id = args.shift.to_s
        if node_id.empty?
          $stderr.puts "Error: neighbors requires a node id"
          exit 1
        end

        relation = parse_single_option(args, "--relation=")
        depth = parse_integer_option(args, "--depth=", default: 1)
        limit = extract_limit(args)
        result = @reviewer.neighbors(node_id, relation: relation, depth: depth, limit: limit)
        output_graph(result)
      end

      def delete_memories(args)
        mode = args.shift.to_s
        case mode
        when "id"
          delete_by_id(args)
        when "last"
          delete_last(args)
        when "all"
          delete_all(args)
        else
          $stderr.puts "Error: delete requires one of: id|last|all"
          exit 1
        end
      end

      def delete_by_id(args)
        id = args.shift.to_s
        if id.empty?
          $stderr.puts "Error: delete id requires a memory id"
          exit 1
        end

        scope = parse_scope_option(args)
        dry_run = parse_boolean_flag(args, "--dry-run")
        result = @memory.delete_memory_by_id(id: id, scope: scope, dry_run: dry_run)
        output_delete(result)
      end

      def delete_last(args)
        limit = extract_limit(args)
        if limit <= 0
          $stderr.puts "Error: delete last requires -n with value > 0"
          exit 1
        end

        scope = parse_scope_option(args)
        type = parse_single_option(args, "--type=")
        agent = parse_single_option(args, "--agent=")
        dry_run = parse_boolean_flag(args, "--dry-run")
        result = @memory.delete_recent(limit: limit, scope: scope, type: type, agent: agent, dry_run: dry_run)
        output_delete(result)
      end

      def delete_all(args)
        scope = parse_scope_option(args)
        type = parse_single_option(args, "--type=")
        agent = parse_single_option(args, "--agent=")
        dry_run = parse_boolean_flag(args, "--dry-run")
        confirmed = parse_boolean_flag(args, "--yes")

        if !dry_run && !confirmed
          $stderr.puts "Error: delete all requires --yes (or use --dry-run)"
          exit 1
        end

        result = @memory.delete_all(scope: scope, type: type, agent: agent, dry_run: dry_run)
        output_delete(result)
      end

      def subgraph(args)
        seeds = args.shift.to_s.split(",").map(&:strip).reject(&:empty?)
        if seeds.empty?
          $stderr.puts "Error: subgraph requires comma-separated seed ids"
          exit 1
        end

        relation_filters = parse_list_option(args, "--relation=")
        depth = parse_integer_option(args, "--depth=", default: 2)
        limit = extract_limit(args, default: 200)
        result = @reviewer.subgraph(seed_ids: seeds, relation_filters: relation_filters, depth: depth, limit: limit)
        output_graph(result)
      end

      def merge_memory_results(*results, limit:)
        entries = results.flat_map { |result| result["memories"] || [] }
        sorted = entries.sort_by { |entry| -(entry["created_at_unix"] || 0) }
        { "memories" => sorted.first(limit), "count" => [sorted.length, limit].min }
      end

      def output(result)
        if result["error"]
          if @json_output
            puts JSON.generate({ "error" => result["error"] })
          else
            $stderr.puts "Error: #{result["error"]}"
          end
          exit 1
        end

        if @json_output
          puts JSON.generate(result)
          return
        end

        if result["count"] == 0
          puts "No memories found."
          return
        end

        memories = result["memories"] || result.values.first

        memories.each do |mem|
          puts format_memory(mem)
          puts "-" * 40
        end
      end

      def output_delete(result)
        if result["error"]
          if @json_output
            puts JSON.generate({ "error" => result["error"] })
          else
            $stderr.puts "Error: #{result['error']}"
          end
          exit 1
        end

        if @json_output
          puts JSON.generate(result)
          return
        end

        action = result["dry_run"] ? "Planned" : "Deleted"
        puts "#{action} #{result['deleted_count']} keys (candidates: #{result['candidate_count']})"
        puts "Mode: #{result['mode']} | Scope: #{result['scope']}"
        filters = result["filters"] || {}
        puts "Filters: type=#{filters['type'] || 'any'}, agent=#{filters['agent'] || 'any'}"
        ids = Array(result["deleted_ids"])
        puts "Memory ids: #{ids.join(', ')}" unless ids.empty?
      end

      def parse_scope_option(args)
        scope = parse_single_option(args, "--scope=") || "project"
        unless %w[project all].include?(scope)
          $stderr.puts "Error: --scope must be project or all"
          exit 1
        end
        scope
      end

      def parse_boolean_flag(args, flag)
        !args.delete(flag).nil?
      end

      def output_graph(result)
        if result["error"]
          if @json_output
            puts JSON.generate({ "error" => result["error"] })
          else
            $stderr.puts "Error: #{result['error']}"
          end
          exit 1
        end

        if @json_output
          puts JSON.generate(result)
          return
        end

        puts "Graph result: #{result['count']} edges"
        puts "Nodes: #{Array(result['nodes']).length}"
        Array(result["edges"]).each do |edge|
          puts "  - #{edge['source_id']} --#{edge['relation']}--> #{edge['target_id']}"
        end
      end

      def format_memory(mem)
        <<~OUTPUT
          [#{mem["type"]&.upcase}] #{mem["title"]}
          #{mem["created_at"]} by #{mem["agent"]}
          #{mem["description"]}
          #{format_code(mem["code_snippet"]) unless mem["code_snippet"].to_s.empty?}
          Tags: #{mem["tags"]&.join(", ") || "none"}
        OUTPUT
      end

      def format_code(snippet)
        return "" if snippet.to_s.empty?

        "\n```\n#{snippet.strip}\n```"
      end

      def show_help
        puts <<~HELP
          Usage: agentf memory <command> [options]

          Commands:
            recent, list              List recent memories (default: 10)
            pitfalls                  List pitfalls (things that went wrong)
            lessons                   List lessons learned
            successes                 List successes
            intents [kind]            List intents (kind: business|feature)
            business-intents          List business intents
            feature-intents           List feature intents
            add-business-intent       Store business intent
            add-feature-intent        Store feature intent
            add-lesson                Store lesson memory
            add-success               Store success memory
            add-pitfall               Store pitfall memory
            tags                      List all unique tags
            search <query>            Search memories by keyword
            delete id <memory_id>     Delete one memory and related edges
            delete last -n <count>    Delete most recent memories
            delete all                Delete memories and graph/task keys
            neighbors <id>            Traverse graph edges from a memory id
            subgraph <ids>            Build graph from comma-separated seed ids
            summary, stats            Show summary statistics
            by-tag <tag>              Get memories with specific tag
            by-agent <agent>          Get memories from specific agent
            by-type <type>            Get memories by type (#{VALID_EPISODE_TYPES.join("|")})

          Options:
            -n <count>               Limit number of results (default: 10)
            --json                   Output in JSON format

          Examples:
            agentf memory recent -n 5
            agentf memory pitfalls
            agentf memory intents business -n 5
            agentf memory add-business-intent "Reliability" "Prioritize uptime" --tags=ops,platform --constraints="No downtime;No vendor lock-in"
            agentf memory add-feature-intent "Agent handoff" "Improve orchestrator continuity" --acceptance="Keeps context;Preserves task state"
            agentf memory add-lesson "Refactor strategy" "Extracted adapter seam" --agent=PLANNER --tags=architecture
            agentf memory add-success "Provider install works" "Installed copilot + opencode manifests" --agent=ENGINEER
            agentf memory search "react"
            agentf memory delete id episode_abcd
            agentf memory delete last -n 10 --scope=project
            agentf memory delete all --scope=all --yes
            agentf memory neighbors episode_abcd --depth=2
            agentf memory by-tag "performance"
            agentf memory summary
        HELP
      end
    end
  end
end
