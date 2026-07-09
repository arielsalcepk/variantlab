# frozen_string_literal: true

module Agent
  # Human-in-the-loop confirmation for destructive tool calls.
  module Gate
    module_function

    # Returns true if the action is approved to run.
    def confirm(name, input)
      return true if ENV["AGENT_AUTO_APPROVE"] == "1"

      puts "\n--- HITL GATE ---"
      puts "Tool:  #{name}"
      puts "Input: #{input}"
      print "Approve this action? [y/N] "
      answer = $stdin.gets&.strip&.downcase
      answer == "y"
    end
  end
end
