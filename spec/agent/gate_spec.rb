# frozen_string_literal: true

require_relative "../../lib/agent/gate"
require "stringio"

RSpec.describe Agent::Gate do
  around do |example|
    original = ENV["AGENT_AUTO_APPROVE"]
    example.run
    if original.nil?
      ENV.delete("AGENT_AUTO_APPROVE")
    else
      ENV["AGENT_AUTO_APPROVE"] = original
    end
  end

  around do |example|
    # Swap the $stdout *global* rather than stubbing methods on the real
    # IO object: Kernel#puts/#print write to a real terminal-backed IO via
    # an internal fast path that bypasses Ruby method dispatch, so
    # `allow($stdout).to receive(:puts)` silently fails to intercept it.
    # A StringIO has no such fast path, so swapping the global reliably
    # swallows the gate's prompt output.
    original_stdout = $stdout
    $stdout = StringIO.new
    begin
      example.run
    ensure
      $stdout = original_stdout
    end
  end

  describe ".confirm" do
    it "auto-approves without prompting when AGENT_AUTO_APPROVE=1" do
      ENV["AGENT_AUTO_APPROVE"] = "1"
      expect($stdin).not_to receive(:gets)

      expect(described_class.confirm("write_file", { "path" => "x" })).to be(true)
    end

    it "prompts and approves when the human answers y" do
      ENV.delete("AGENT_AUTO_APPROVE")
      allow($stdin).to receive(:gets).and_return("y\n")

      expect(described_class.confirm("write_file", { "path" => "x" })).to be(true)
    end

    it "approves case-insensitively and trims surrounding whitespace" do
      ENV.delete("AGENT_AUTO_APPROVE")
      allow($stdin).to receive(:gets).and_return(" Y \n")

      expect(described_class.confirm("write_file", {})).to be(true)
    end

    it "rejects any answer other than y" do
      ENV.delete("AGENT_AUTO_APPROVE")
      allow($stdin).to receive(:gets).and_return("n\n")

      expect(described_class.confirm("write_file", {})).to be(false)
    end

    it "rejects an empty answer" do
      ENV.delete("AGENT_AUTO_APPROVE")
      allow($stdin).to receive(:gets).and_return("\n")

      expect(described_class.confirm("write_file", {})).to be(false)
    end

    it "rejects when stdin returns nil (e.g. EOF / non-interactive session)" do
      ENV.delete("AGENT_AUTO_APPROVE")
      allow($stdin).to receive(:gets).and_return(nil)

      expect(described_class.confirm("write_file", {})).to be(false)
    end

    it "does not treat any value other than the string '1' as auto-approve" do
      ENV["AGENT_AUTO_APPROVE"] = "true"
      allow($stdin).to receive(:gets).and_return("n\n")

      expect(described_class.confirm("write_file", {})).to be(false)
    end
  end
end
