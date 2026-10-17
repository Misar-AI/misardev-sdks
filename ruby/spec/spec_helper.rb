# frozen_string_literal: true

require "json"
require "webmock/rspec"
require "misardev"

WebMock.disable_net_connect!

# Records every request and answers from a queue. The last queued answer is
# repeated once the queue runs dry, so "always 429" is a one-element queue.
class FakeHttp
  Stream = Struct.new(:status, :headers, :chunks, keyword_init: true)

  attr_reader :requests

  def initialize(responses = [])
    @responses = responses.dup
    @requests = []
  end

  def call(request)
    @requests << request
    nxt = next_response
    raise nxt if nxt.is_a?(Exception)
    return MisarDev::Core::Response.new(status: nxt.status, headers: nxt.headers, body: nxt.chunks.join, reason: "") if nxt.is_a?(Stream)

    nxt
  end

  def stream(request)
    @requests << request
    nxt = next_response
    raise nxt if nxt.is_a?(Exception)

    chunks = nxt.is_a?(Stream) ? nxt.chunks : [nxt.body]
    yield(MisarDev::Core::StreamResponse.new(status: nxt.status, headers: nxt.headers, reason: nxt.respond_to?(:reason) ? nxt.reason.to_s : "") do |&blk|
      chunks.each(&blk)
    end)
  end

  # The decoded JSON body of request +i+.
  def body(i = 0)
    raw = @requests[i].body
    raw.nil? ? nil : JSON.parse(raw)
  end

  private

  def next_response
    return FakeHttp.json("ok" => true) if @responses.empty?

    @responses.length > 1 ? @responses.shift : @responses.first
  end

  class << self
    def json(body, status = 200, headers = {})
      MisarDev::Core::Response.new(
        status: status,
        headers: { "content-type" => "application/json" }.merge(headers.transform_keys(&:downcase)),
        body: JSON.generate(body),
        reason: ""
      )
    end

    def raw(status, body = "", reason = "")
      MisarDev::Core::Response.new(status: status, headers: {}, body: body, reason: reason)
    end

    # Each frame is delivered as its own chunk.
    def sse(frames, status = 200)
      Stream.new(status: status, headers: { "content-type" => "text/event-stream" }, chunks: frames)
    end
  end
end

module Helpers
  def client(responses = [], max_retries: 3)
    http = FakeHttp.new(responses)
    [MisarDev::Client.new("mdk_test_key", base_url: "https://api.test/dev", max_retries: max_retries, http_client: http), http]
  end

  def plan_limit_body
    JSON.parse(<<~JSON)
      {"error":"API access requires the Pro plan or higher.","code":"plan_limit_exceeded","requiredPlan":"pro",
       "upgrade":{"product":"dev","product_name":"Misar.Dev","reason":"feature_locked","feature":"api_access",
       "feature_label":"API access","headline":"API access isn't included in your Starter plan.","usage":null,
       "current_plan":{"slug":"starter","name":"Starter"},"recommended_plan":"pro","plans":[],"topup":null,
       "overage":null,"trial":null,"cross_sell":[],
       "urls":{"pricing":"https://www.misar.dev/pricing","billing":"https://www.misar.dev/settings/billing",
       "docs":"https://docs.misar.io/dev/api","compare":"https://www.misar.dev/pricing#compare"},
       "cta":"Upgrade to Pro to continue."}}
    JSON
  end
end

RSpec.configure do |config|
  config.include Helpers
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
