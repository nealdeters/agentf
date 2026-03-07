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
        agent = parse_single_option(args, "--agent=") || "SPECIALIST"
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
            agentf memory add-lesson "Refactor strategy" "Extracted adapter seam" --agent=ARCHITECT --tags=architecture
            agentf memory add-success "Provider install works" "Installed copilot + opencode manifests" --agent=SPECIALIST
            agentf memory search "react"
            agentf memory by-tag "performance"
            agentf memory summary
        HELP
      end
    end
  end
end
