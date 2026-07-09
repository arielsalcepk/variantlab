# frozen_string_literal: true

module Agent
  # Owns the spec -> execute -> verify tool-use loop that drives a single
  # agent task from start to finish.
  class Runner
    DEFAULT_MAX_ITERATIONS = 25

    Result = Struct.new(:status, :message, :transcript, keyword_init: true)

    # client:         an Agent::Client (or anything responding to #send_message)
    # tools:          the tools module (defaults to Agent::Tools)
    # gate:           the HITL gate (defaults to Agent::Gate)
    # system_prompt:  full system prompt string (see .build_system_prompt)
    # max_iterations: hard cap on loop turns
    # out:            where progress output is written (defaults to $stdout;
    #                 pass a StringIO in tests to capture it)
    def initialize(client:, system_prompt:, tools: Agent::Tools, gate: Agent::Gate,
                   max_iterations: DEFAULT_MAX_ITERATIONS, out: $stdout)
      @client = client
      @tools = tools
      @gate = gate
      @system_prompt = system_prompt
      @max_iterations = max_iterations
      @out = out
    end

    # Runs a task to completion. Returns a Result with status one of:
    #   :done            - the agent stopped calling tools on its own
    #   :max_iterations   - the iteration cap was hit first
    #   :api_error        - the API call raised
    def run(task)
      messages = [ { role: "user", content: task } ]
      transcript = []
      iteration = 0

      loop do
        iteration += 1

        if iteration > @max_iterations
          msg = "Stopped: reached the #{@max_iterations}-iteration limit without the agent declaring the task done."
          @out.puts "\n#{msg}"
          return Result.new(status: :max_iterations, message: msg, transcript: transcript)
        end

        response = begin
          @client.send_message(messages: messages, tools: @tools::SCHEMAS, system: @system_prompt)
        rescue Agent::Client::ApiError => e
          msg = "API call failed - #{e.message}"
          @out.puts "\nAgent stopped: #{msg}"
          return Result.new(status: :api_error, message: msg, transcript: transcript)
        end

        content = response["content"]
        messages << { role: "assistant", content: content }

        content.select { |b| b["type"] == "text" }.each do |b|
          @out.puts b["text"]
          transcript << { type: :text, text: b["text"] }
        end

        tool_uses = content.select { |b| b["type"] == "tool_use" }

        if tool_uses.empty?
          return Result.new(status: :done, message: "Task completed.", transcript: transcript)
        end

        tool_results = tool_uses.map do |tu|
          name  = tu["name"]
          input = tu["input"]

          result = if @tools.destructive?(name, input) && !@gate.confirm(name, input)
                     "REJECTED by human reviewer. Do not retry the same action; revise your plan instead."
          else
                     @tools.call(name, input)
          end

          @out.puts "\n[tool] #{name}(#{input}) =>\n#{result}\n"
          transcript << { type: :tool_call, name: name, input: input, result: result }

          { type: "tool_result", tool_use_id: tu["id"], content: result.to_s }
        end

        messages << { role: "user", content: tool_results }
      end
    end

    # Builds the full system prompt for a run: the fixed agent-loop
    # instructions, plus the project's own guardrails loaded from CLAUDE.md
    def self.build_system_prompt(claude_md_path:, max_iterations: DEFAULT_MAX_ITERATIONS)
      guardrails =
        if File.exist?(claude_md_path)
          File.read(claude_md_path)
        else
          warn "WARNING: CLAUDE.md not found at #{claude_md_path} - running without project guardrails."
          ""
        end

      <<~SYS
        You are a coding agent working inside a Rails/Solidus project called VariantLab.
        Follow this loop strictly:
          1. SPEC: restate the task as a short numbered plan before touching anything.
          2. EXECUTE: use the available tools to read relevant files, then make the
             smallest change that satisfies the plan.
          3. VERIFY: run the relevant tests or commands to confirm the change works.
        Rules:
          - Read a file before editing it. Never write a file you have not read this session.
          - Prefer the smallest diff that solves the task.
          - write_file and any non-read-only run_command call are gated by a human
            approval step - expect some calls to be rejected, and adapt your plan.
          - When you believe the task is complete and verified, say so explicitly
            and stop calling tools.
          - You have a hard limit of #{max_iterations} tool-use turns for this task.
            Work efficiently and don't waste turns on redundant reads.

        The project's own guardrails follow below (from CLAUDE.md). These are
        binding, take precedence over convenience, and are not to be revisited or
        argued around:

        #{guardrails}
      SYS
    end
  end
end
