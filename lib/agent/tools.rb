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
        description: "Read the full contents of a file, given a path relative to the project root.",
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
                      "DESTRUCTIVE - gated by human confirmation.",
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
                      "AND contains no shell chaining/redirection.",
        input_schema: {
          type: "object",
          properties: { command: { type: "string" } },
          required: [ "command" ]
        }
      }
    ].freeze

    READ_ONLY_COMMAND_PREFIXES = [
      "bin/rails test", "bin/rspec", "rspec", "bundle exec rspec",
      "bin/rails db:test", "git status", "git diff", "git log"
    ].freeze

    # Any of these characters let a command escape a simple prefix
    # check (chaining, piping, redirection, substitution, backgrounding,
    # newlines). If present, the command is ALWAYS treated as destructive,
    # regardless of what it starts with.
    SHELL_METACHARACTERS = /[;&|`$<>\n]/.freeze

    module_function

    def read_file(path:)
      full = safe_path(path)
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
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
      "OK: wrote #{content.bytesize} bytes to #{path}"
    end

    def run_command(command:)
      stdout, stderr, status = Open3.capture3(command, chdir: ROOT)
      "exit=#{status.exitstatus}\n--- stdout ---\n#{stdout}\n--- stderr ---\n#{stderr}"
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
  end
end
