# frozen_string_literal: true

module Agent
  # Human-in-the-loop confirmation for destructive tool calls.
  module Gate
    module_function

    # Returns true if the action is approved to run.
    def confirm(name, input)
      if ENV["AGENT_AUTO_APPROVE"] == "1"
        # AGENT_AUTO_APPROVE is a total, silent bypass of the HITL
        # gate. If it's left set in a shell from an earlier test run, every
        # future run, including ones touching real files, would approve
        # silently with no indication anything unusual happened. Make it
        # loud and impossible to miss instead.
        puts "\n#{'!' * 70}"
        puts "! AGENT_AUTO_APPROVE=1 is set - auto-approving WITHOUT confirmation !"
        puts "! Tool:  #{name}"
        puts "! Input: #{input}"
        puts "!" * 70
        return true
      end

      puts "\n--- HITL GATE ---"
      puts "Tool:  #{name}"
      puts "Input: #{input}"
      print "Approve this action? [y/N] "
      answer = $stdin.gets&.strip&.downcase
      answer == "y"
    end
  end
end
