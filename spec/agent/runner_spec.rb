# frozen_string_literal: true

require_relative "../../lib/agent/client"
require_relative "../../lib/agent/runner"
require "stringio"
require "tmpdir"

RSpec.describe Agent::Runner do
  let(:fake_out) { StringIO.new }

  def text_response(text_value)
    { "content" => [ { "type" => "text", "text" => text_value } ] }
  end

  def tool_use_response(name:, input:, id: "tool_1")
    { "content" => [ { "type" => "tool_use", "name" => name, "input" => input, "id" => id } ] }
  end

  # A minimal fake client: given a fixed list of responses (or exceptions to
  # raise), returns them one at a time as #send_message is called.
  def fake_client(*responses)
    call_count = 0
    client = double("client")
    allow(client).to receive(:send_message) do |**_kwargs|
      response = responses[call_count]
      raise "fake_client called more times (#{call_count + 1}) than responses were stubbed (#{responses.size})" unless response

      call_count += 1
      raise response if response.is_a?(Exception)

      response
    end
    client
  end

  let(:noop_tools) do
    Class.new do
      # const_set, not a bare `SCHEMAS = ...`: constant assignment inside a
      # Class.new do...end block follows lexical scope, not the block's
      # self, so a bare assignment here would leak SCHEMAS onto the spec
      # file's top-level scope instead of defining it on this class.
      const_set(:SCHEMAS, [ { name: "noop" } ].freeze)

      def self.destructive?(_name, _input)
        false
      end

      def self.call(_name, _input)
        "ok"
      end
    end
  end

  let(:auto_approve_gate) do
    Class.new do
      def self.confirm(_name, _input)
        true
      end
    end
  end

  describe "#run" do
    it "returns :done as soon as a response has no tool_use blocks" do
      client = fake_client(text_response("all done"))
      runner = described_class.new(client: client, tools: noop_tools, gate: auto_approve_gate,
                                    system_prompt: "sys", out: fake_out)

      result = runner.run("do the thing")

      expect(result.status).to eq(:done)
      expect(fake_out.string).to include("all done")
    end

    it "executes a tool call and feeds the result back before finishing" do
      client = fake_client(
        tool_use_response(name: "noop", input: {}),
        text_response("done after tool")
      )
      runner = described_class.new(client: client, tools: noop_tools, gate: auto_approve_gate,
                                    system_prompt: "sys", out: fake_out)

      result = runner.run("do the thing")

      expect(result.status).to eq(:done)
      expect(fake_out.string).to include("[tool] noop")
    end

    it "stops cleanly at the iteration cap instead of looping forever" do
      # Every response requests another tool call - without a cap this would
      # never terminate on its own.
      client = fake_client(*Array.new(10) { tool_use_response(name: "noop", input: {}) })
      runner = described_class.new(client: client, tools: noop_tools, gate: auto_approve_gate,
                                    system_prompt: "sys", max_iterations: 3, out: fake_out)

      result = runner.run("do the thing")

      expect(result.status).to eq(:max_iterations)
      expect(result.message).to include("3-iteration limit")
      expect(fake_out.string).to include("reached the 3-iteration limit")
    end

    it "stops cleanly (not an uncaught exception) when the API call fails" do
      client = fake_client(Agent::Client::ApiError.new("Anthropic API error 429: rate limited"))
      runner = described_class.new(client: client, tools: noop_tools, gate: auto_approve_gate,
                                    system_prompt: "sys", out: fake_out)

      result = nil
      expect { result = runner.run("do the thing") }.not_to raise_error

      expect(result.status).to eq(:api_error)
      expect(result.message).to include("429")
    end

    it "asks the gate before a destructive tool call and honors a rejection" do
      destructive_tools = Class.new do
        const_set(:SCHEMAS, [ { name: "write_file" } ].freeze)

        def self.destructive?(_name, _input)
          true
        end

        def self.call(_name, _input)
          raise "should not be called when the gate rejects"
        end
      end

      rejecting_gate = Class.new do
        def self.confirm(_name, _input)
          false
        end
      end

      client = fake_client(
        tool_use_response(name: "write_file", input: { "path" => "x", "content" => "y" }),
        text_response("gave up after rejection")
      )
      runner = described_class.new(client: client, tools: destructive_tools, gate: rejecting_gate,
                                    system_prompt: "sys", out: fake_out)

      result = runner.run("do the thing")

      expect(result.status).to eq(:done)
      expect(fake_out.string).to include("REJECTED by human reviewer")
    end

    it "does not consult the gate for a non-destructive tool call" do
      gate_that_should_not_be_called = Class.new do
        def self.confirm(_name, _input)
          raise "gate should not be consulted for non-destructive calls"
        end
      end

      runner = described_class.new(
        client: fake_client(tool_use_response(name: "noop", input: {}), text_response("done")),
        tools: noop_tools,
        gate: gate_that_should_not_be_called,
        system_prompt: "sys",
        out: fake_out
      )

      expect { runner.run("do the thing") }.not_to raise_error
    end
  end

  describe ".build_system_prompt" do
    it "includes the actual CLAUDE.md contents when the file exists" do
      Dir.mktmpdir do |dir|
        claude_md = File.join(dir, "CLAUDE.md")
        File.write(claude_md, "## Never\n- Never do the bad thing\n")

        prompt = described_class.build_system_prompt(claude_md_path: claude_md)

        expect(prompt).to include("Never do the bad thing")
      end
    end

    it "still returns a usable prompt, with a stderr warning, when CLAUDE.md is missing" do
      missing_path = "/tmp/definitely_not_here_#{Process.pid}/CLAUDE.md"
      prompt = nil

      expect { prompt = described_class.build_system_prompt(claude_md_path: missing_path) }
        .to output(/WARNING: CLAUDE\.md not found/).to_stderr

      expect(prompt).to include("You are a coding agent")
    end

    it "embeds the iteration limit it was given so the model knows its own budget" do
      # claude_md_path is deliberately missing here too, which fires the same
      # stderr warning as the test above - silence it the same way since this
      # test isn't about the warning, just the embedded iteration count.
      prompt = nil
      expect { prompt = described_class.build_system_prompt(claude_md_path: "/nonexistent", max_iterations: 7) }
        .to output.to_stderr
      expect(prompt).to include("hard limit of 7 tool-use turns")
    end
  end
end
