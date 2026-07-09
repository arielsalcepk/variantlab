# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Agent
  # Thin wrapper around the Anthropic Messages API with tool-use support.
  class Client
    API_URL = "https://api.anthropic.com/v1/messages"
    DEFAULT_MODEL = ENV.fetch("AGENT_MODEL", "claude-sonnet-5")
    MAX_TOKENS = Integer(ENV.fetch("AGENT_MAX_TOKENS", "4096"))

    class ApiError < StandardError; end

    def initialize(api_key: ENV.fetch("ANTHROPIC_API_KEY"), model: DEFAULT_MODEL)
      @api_key = api_key
      @model = model
    end

    # messages: [{ role:, content: }, ...]
    # tools: [{ name:, description:, input_schema: }, ...]
    # Returns the parsed response body (Hash).
    def send_message(messages:, tools: [], system: nil)
      uri = URI(API_URL)
      req = Net::HTTP::Post.new(uri)
      req["content-type"] = "application/json"
      req["x-api-key"] = @api_key
      req["anthropic-version"] = "2023-06-01"

      body = {
        model: @model,
        max_tokens: MAX_TOKENS,
        messages: messages
      }
      body[:system] = system if system
      body[:tools] = tools unless tools.empty?

      req.body = JSON.generate(body)

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

      raise ApiError, "Anthropic API error #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    end
  end
end
