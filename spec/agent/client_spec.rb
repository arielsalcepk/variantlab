# frozen_string_literal: true

require_relative "../../lib/agent/client"
require "json"

RSpec.describe Agent::Client do
  subject(:client) { described_class.new(api_key: "test-key", model: "claude-sonnet-5") }

  # Stubs Net::HTTP.start so no real network call happens. Captures the
  # request that was built so specs can assert on headers/body, and returns
  # a fake response with the given success/body.
  def stub_http(status_ok:, body:)
    fake_http = double("http")

    allow(Net::HTTP).to receive(:start) do |*_args, **_kwargs, &blk|
      blk.call(fake_http)
    end

    fake_response = double("response", body: body, code: status_ok ? "200" : "429")
    allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(status_ok)

    allow(fake_http).to receive(:request) do |req|
      @sent_request = req
      fake_response
    end
  end

  describe "#send_message" do
    it "sends model, messages, system and tools in the request body" do
      stub_http(status_ok: true, body: { "content" => [{ "type" => "text", "text" => "hi" }] }.to_json)

      client.send_message(
        messages: [{ role: "user", content: "hello" }],
        tools: [{ name: "read_file" }],
        system: "be nice"
      )

      body = JSON.parse(@sent_request.body)
      expect(body["model"]).to eq("claude-sonnet-5")
      expect(body["system"]).to eq("be nice")
      expect(body["tools"]).to eq([{ "name" => "read_file" }])
      expect(body["messages"]).to eq([{ "role" => "user", "content" => "hello" }])
    end

    it "omits the system and tools keys entirely when not given" do
      stub_http(status_ok: true, body: { "content" => [] }.to_json)

      client.send_message(messages: [{ role: "user", content: "hi" }])

      body = JSON.parse(@sent_request.body)
      expect(body).not_to have_key("system")
      expect(body).not_to have_key("tools")
    end

    it "sets the required auth and versioning headers" do
      stub_http(status_ok: true, body: { "content" => [] }.to_json)

      client.send_message(messages: [{ role: "user", content: "hi" }])

      expect(@sent_request["x-api-key"]).to eq("test-key")
      expect(@sent_request["anthropic-version"]).to eq("2023-06-01")
      expect(@sent_request["content-type"]).to eq("application/json")
    end

    it "returns the parsed JSON response on success" do
      stub_http(status_ok: true, body: { "content" => [{ "type" => "text", "text" => "ok" }] }.to_json)

      result = client.send_message(messages: [{ role: "user", content: "hi" }])

      expect(result["content"].first["text"]).to eq("ok")
    end

    it "raises Agent::Client::ApiError on a non-success response, including the code and body" do
      stub_http(status_ok: false, body: '{"error":"rate_limited"}')

      expect { client.send_message(messages: [{ role: "user", content: "hi" }]) }
        .to raise_error(Agent::Client::ApiError, /429/)
    end
  end

  describe "defaults" do
    it "falls back to ANTHROPIC_API_KEY from the environment when no api_key is given" do
      original = ENV["ANTHROPIC_API_KEY"]
      ENV["ANTHROPIC_API_KEY"] = "env-key"

      begin
        stub_http(status_ok: true, body: { "content" => [] }.to_json)
        described_class.new.send_message(messages: [{ role: "user", content: "hi" }])
        expect(@sent_request["x-api-key"]).to eq("env-key")
      ensure
        if original.nil?
          ENV.delete("ANTHROPIC_API_KEY")
        else
          ENV["ANTHROPIC_API_KEY"] = original
        end
      end
    end
  end
end
