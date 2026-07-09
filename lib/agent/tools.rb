# frozen_string_literal: true

require "open3"
require "fileutils"

module Agent
  # Defines the tools the agent can call, plus their JSON schemas for the API
  # and the Ruby implementations that actually run them.
  module Tools
    ROOT = Dir.pwd

    SCHEMAS = [
      {
        name: "read_file",
        description: "Read the full contents of a file, given a path relative to the project root. " \
                      "Refuses paths that look like secrets/credentials (.env, master.key, etc).",
        input_schema: {
          type: "object",
          properties: { path: { type: "string" } },
          required: [ "path" ]
        }
      },
      {
        name: "list_files",
        description: "List files under a directory (relative to project root), recursively, " \
                      "skipping node_modules/.git/tmp/log/storage.",
        input_schema: {
          type: "object",
          properties: {
            path: { type: "string", description: "Directory to list, e.g. 'app/models'. Use '.' for project root." }
          },
          required: [ "path" ]
        }
      },
      {
        name: "write_file",
        description: "Write (create or overwrite) a file with the given content. " \
                      "DESTRUCTIVE - gated by human confirmation. Additionally refuses, " \
                      "unconditionally, to touch the agent's own safety code or secret/credential paths.",
        input_schema: {
          type: "object",
          properties: {
            path: { type: "string" },
            content: { type: "string" }
          },
          required: %w[path content]
        }
      },
      {
        name: "run_command",
        description: "Run a shell command in the project root, return stdout/stderr/exit status. " \
                      "Gated by human confirmation unless it matches the read-only allowlist (tests, git status/diff/log) " \
                      "AND contains no shell chaining/redirection. A short list of catastrophic patterns " \
                      "(e.g. rm -rf /) are refused unconditionally. Commands are killed if they run too long.",
        input_schema: {
          type: "object",
          properties: { command: { type: "string" } },
          required: [ "command" ]
        }
      }
    ].freeze

    # Every entry here must be guaranteed to run inside the project's
    # Bundler context (either via a generated binstub, which bootstraps
    # bundler/setup itself, or an explicit "bundle exec"). A bare "rspec"
    # is deliberately excluded: it resolves against $PATH, not Gemfile.lock,
    # and could silently run a different rspec version than the one pinned.
    READ_ONLY_COMMAND_PREFIXES = [
      "bin/rails test", "bin/rspec", "bundle exec rspec",
      "bin/rails db:test", "git status", "git diff", "git log"
    ].freeze

    # Any of these characters let a command escape a simple prefix
    # check (chaining, piping, redirection, substitution, backgrounding,
    # newlines). If present, the command is ALWAYS treated as destructive,
    # regardless of what it starts with.
    SHELL_METACHARACTERS = /[;&|`$<>\n]/.freeze

    # Paths that must never be overwritten by the agent, full stop -
    # regardless of gate approval or AGENT_AUTO_APPROVE. This is a hard,
    # code-level boundary. CLAUDE.md *tells* the model never to weaken its
    # own gate, but that's a request to the model's judgment (and to a human
    # not rushing through an approval prompt), not an enforced boundary -
    # this closes that gap in code.
    PROTECTED_FROM_WRITE = [
      "lib/agent/client.rb",
      "lib/agent/tools.rb",
      "lib/agent/gate.rb",
      "lib/agent/runner.rb",
      "bin/agent",
      "CLAUDE.md"
    ].freeze

    # Paths that look like secrets or credentials. Blocked from
    # both write (can't be silently replaced or emptied) and read (can't be
    # leaked into the model's conversation, printed to the terminal, or sent
    # to the Anthropic API as part of a tool result).
    SECRET_PATH_PATTERNS = [
      %r{(^|/)\.env(\..+)?$},
      %r{(^|/)config/master\.key$},
      %r{(^|/)config/credentials(/.+)?\.key$},
      %r{(^|/)config/credentials\.yml\.enc$},
      %r{(^|/)id_rsa(\.pub)?$},
      %r{(^|/)id_ed25519(\.pub)?$},
      /\.pem$/,
      /\.p12$/,
      %r{(^|/)\.secrets(/|$)}
    ].freeze

    # Commands that are refused outright, unconditionally - not even
    # a human "y" at the gate can approve them. Deliberately a very short
    # list of unambiguous, catastrophic patterns (wiping a filesystem root,
    # a fork bomb, writing directly to a block device). This is insurance
    # against one bad copy-paste-approve moment during a long session, not a
    # general security boundary.
    CATASTROPHIC_COMMAND_PATTERNS = [
      %r{\brm\s+.*-[a-zA-Z]*r[a-zA-Z]*f\b.*\s/(\s|$)},  # rm -rf / (or -fr, interspersed flags, etc.)
      /\brm\s+.*-[a-zA-Z]*r[a-zA-Z]*f\b.*\s~(\s|\/|$)/, # rm -rf ~
      /\bmkfs\b/,
      %r{\bdd\b.*\bof=/dev/},
      /:\(\)\s*\{\s*:\|:&\s*\}\s*;\s*:/,                # classic fork bomb
      %r{\bchmod\s+-R\s+000\s+/(\s|$)}
    ].freeze

    # Hard cap on how long a single run_command may run before it's
    # killed and reported as timed out, so a hung/backgrounded process can't
    # block the whole agent run indefinitely. Not exposed to the model via
    # the tool schema - only overridable from Ruby (env default, or an
    # explicit kwarg in tests) so the model can't request its way around it.
    COMMAND_TIMEOUT_SECONDS = Integer(ENV.fetch("AGENT_COMMAND_TIMEOUT", "60"))

    module_function

    def read_file(path:)
      full = safe_path(path)

      if secret_path?(full)
        return "ERROR: refusing to read a path that looks like a secret/credential file: #{path}. " \
               "Retrieve its value manually outside the agent if you need it."
      end

      return "ERROR: file not found: #{path}" unless File.exist?(full)

      File.read(full)
    end

    def list_files(path: ".")
      full = safe_path(path)
      return "ERROR: not a directory: #{path}" unless Dir.exist?(full)

      Dir.glob("#{full}/**/*")
         .reject { |f| f =~ %r{/(node_modules|\.git|tmp|log|storage)/} }
         .map { |f| f.sub("#{ROOT}/", "") }
         .join("\n")
    end

    def write_file(path:, content:)
      full = safe_path(path)

      if protected_from_write?(full)
        return "ERROR: refusing to write to a protected path (agent safety code, CLAUDE.md, " \
               "or a secret/credential file): #{path}. Edit this file manually, not through the agent."
      end

      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
      "OK: wrote #{content.bytesize} bytes to #{path}"
    end

    # timeout: not part of the model-facing schema - only settable directly
    # in Ruby (tests, or a future trusted caller). See COMMAND_TIMEOUT_SECONDS.
    def run_command(command:, timeout: COMMAND_TIMEOUT_SECONDS)
      if catastrophic?(command)
        return "ERROR: refusing to run this command under any circumstances - it matches a " \
               "known-catastrophic pattern (e.g. wiping a filesystem root). This is a hard-coded " \
               "block that cannot be approved around, even by a human at the gate."
      end

      stdout_str = +""
      stderr_str = +""
      exit_status = nil
      timed_out = false

      Open3.popen3(command, chdir: ROOT, pgroup: true) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        stdout_reader = Thread.new { stdout_str << stdout.read }
        stderr_reader = Thread.new { stderr_str << stderr.read }

        unless wait_thr.join(timeout)
          timed_out = true
          begin
            # A negative pid targets the whole process group (standard POSIX
            # kill(2) convention), not just the immediate child - so a
            # command that spawned its own children gets fully killed too.
            Process.kill("KILL", -wait_thr.pid)
          rescue Errno::ESRCH, Errno::EPERM
            # Process already exited, or we lack permission to signal it -
            # best effort only, nothing more to do here.
          end
          wait_thr.join
        end

        stdout_reader.join
        stderr_reader.join
        exit_status = wait_thr.value
      end

      return "ERROR: command timed out after #{timeout}s and was killed: #{command}" if timed_out

      "exit=#{exit_status.exitstatus}\n--- stdout ---\n#{stdout_str}\n--- stderr ---\n#{stderr_str}"
    end

    def destructive?(name, input)
      case name
      when "write_file" then true
      when "run_command"
        command = input["command"].to_s

        # Reject the "safe" classification outright if the command
        # contains any shell metacharacter, even if it starts with an
        # allowlisted prefix (e.g. "git status && rm -rf app").
        return true if command =~ SHELL_METACHARACTERS

        # Require the prefix to be the whole command or be
        # followed by a word boundary (space), so "git statusfoo" doesn't
        # slip through as "git status".
        !READ_ONLY_COMMAND_PREFIXES.any? { |p| command == p || command.start_with?("#{p} ") }
      else
        false
      end
    end

    def call(name, input)
      case name
      when "read_file"   then read_file(path: input["path"])
      when "list_files"  then list_files(path: input["path"] || ".")
      when "write_file"  then write_file(path: input["path"], content: input["content"])
      when "run_command" then run_command(command: input["command"])
      else "ERROR: unknown tool #{name}"
      end
    end

    def safe_path(path)
      full = File.expand_path(path, ROOT)

      # Require ROOT to be matched as a full path segment, not just a
      # string prefix, so a sibling dir like "variantlab-scratch" can't pass
      # a check against ROOT "variantlab".
      root_with_sep = ROOT.end_with?(File::SEPARATOR) ? ROOT : "#{ROOT}#{File::SEPARATOR}"
      unless full == ROOT || full.start_with?(root_with_sep)
        raise "Refusing to touch a path outside the project root: #{path}"
      end

      full
    end

    def protected_from_write?(full)
      PROTECTED_FROM_WRITE.include?(relative_path(full)) || secret_path?(full)
    end

    def secret_path?(full)
      rel = relative_path(full)
      SECRET_PATH_PATTERNS.any? { |pattern| pattern.match?(rel) }
    end

    def relative_path(full)
      full.sub("#{ROOT}/", "")
    end

    def catastrophic?(command)
      CATASTROPHIC_COMMAND_PATTERNS.any? { |pattern| pattern.match?(command.to_s) }
    end
  end
end
