# frozen_string_literal: true

require "json"
require "time"

require_relative "../errors"
require_relative "../version"
require_relative "http"
require_relative "sse"

module MisarDev
  module Core
    # HTTP transport shared by the generated resource layer.
    #
    # Everything the SDK does goes through here, and it authenticates exactly
    # one way: the account API key (mdk_…), sent as a bearer token. There is no
    # second credential path. What a key may do — and how much of it — is
    # decided server-side from the subscription behind that key; the SDK carries
    # the key and surfaces the answer rather than deciding locally.
    class Transport
      DEFAULT_BASE_URL = "https://api.misar.io/dev"

      # Statuses worth retrying. 429 only when it is NOT a plan limit.
      RETRYABLE = [429, 500, 502, 503, 504].freeze

      # A 5xx or a dropped connection on a POST may already have done its work —
      # started a build, charged an allowance. Only requests that are safe to
      # repeat are retried on those; a 429 is always safe because the server
      # refused it before doing anything.
      IDEMPOTENT = %w[GET HEAD OPTIONS PUT DELETE].freeze

      MAX_BACKOFF = 60.0

      attr_reader :base_url, :max_retries, :timeout

      def initialize(api_key = nil, base_url: nil, max_retries: 3, timeout: 60, http_client: nil, headers: {})
        key = present(api_key) || present(ENV["MISARDEV_API_KEY"])
        if key.nil?
          raise MisarDevError.new(
            0,
            "A MisarDev API key is required. Pass it to the client or set MISARDEV_API_KEY. " \
            "Create one at https://www.misar.dev/settings/api-keys.",
            code: "missing_api_key"
          )
        end

        @api_key = key
        @base_url = (present(base_url) || present(ENV["MISARDEV_BASE_URL"]) || DEFAULT_BASE_URL).sub(%r{/+\z}, "")
        @max_retries = [1, max_retries.to_i].max
        @timeout = timeout
        @http = http_client || NetHttpClient.new
        @headers = headers || {}
      end

      def inspect
        "#<#{self.class.name} base_url=#{@base_url.inspect}>"
      end

      # ── Helpers ───────────────────────────────────────────────────────────

      UNRESERVED = /[^A-Za-z0-9\-._~]/.freeze

      # Percent-encode everything but RFC 3986 unreserved characters:
      # "a b/c" → "a%20b%2Fc".
      def self.encode(value)
        value.to_s.b.gsub(UNRESERVED) { |c| format("%%%02X", c.ord) }
      end

      # Path-segment encoding for a path parameter.
      def self.segment(value)
        encode(value)
      end

      # Build a query string. nil values are dropped, booleans are sent as
      # true/false, an Array value repeats the key.
      def self.build_query(query)
        return "" if query.nil? || query.empty?

        pairs = []
        query.each do |key, value|
          (value.is_a?(Array) ? value : [value]).each do |v|
            next if v.nil?

            pairs << "#{encode(key)}=#{encode(v)}"
          end
        end
        pairs.empty? ? "" : "?#{pairs.join('&')}"
      end

      # Copy of +body+ with "stream" => true, whatever key style the caller used.
      def self.force_stream(body)
        (body || {}).reject { |k, _| k.to_s == "stream" }.merge("stream" => true)
      end

      # Seconds to wait before the next attempt: Retry-After when sent, else
      # exponential (250 ms · 2^attempt) with jitter; capped at 60 s.
      def self.backoff(attempt, retry_after = nil)
        hinted = retry_after_seconds(retry_after)
        return [hinted, MAX_BACKOFF].min if hinted

        base = 0.25 * (2**attempt)
        [base + (rand * base * 0.25), MAX_BACKOFF].min
      end

      # Parse a Retry-After header — delta seconds or an HTTP-date — into seconds.
      def self.retry_after_seconds(value)
        return nil if value.nil? || value.to_s.strip.empty?

        s = value.to_s.strip
        if s.match?(/\A\d+(\.\d+)?\z/)
          s.to_f
        else
          [Time.httpdate(s) - Time.now, 0].max.to_f
        end
      rescue ArgumentError
        nil
      end

      # True when a body is the plan-limit refusal.
      def self.plan_limit_body?(body)
        body.is_a?(Hash) && body["code"] == "plan_limit_exceeded"
      end

      # Pull a human message out of the API's several error shapes.
      def self.message_of(body, fallback)
        if body.is_a?(Hash)
          return body["error"] if body["error"].is_a?(String)
          # /v1/* answers in the OpenAI shape: { error: { message, type, code } }
          return body["error"]["message"] if body["error"].is_a?(Hash) && body["error"]["message"].is_a?(String)
          return body["message"] if body["message"].is_a?(String)
        end
        return body.strip[0, 500] if body.is_a?(String) && !body.strip.empty?

        fallback
      end

      def self.code_of(body)
        return nil unless body.is_a?(Hash)
        return body["code"] if body["code"].is_a?(String)
        return body["error"]["code"] if body["error"].is_a?(Hash) && body["error"]["code"].is_a?(String)

        nil
      end

      # Map an error response to the right typed error. Plan limits first, by code.
      def self.error_for(status, headers, body, reason = "")
        headers ||= {}
        request_id = headers["x-request-id"]
        message = message_of(body, reason.to_s.empty? ? "HTTP #{status}" : reason.to_s)
        code = code_of(body)
        common = { code: code, body: body, request_id: request_id }

        if plan_limit_body?(body)
          return PlanLimitError.new(
            status, message,
            offer: body["upgrade"].is_a?(Hash) ? body["upgrade"] : nil,
            retry_after: retry_after_seconds(headers["retry-after"]),
            body: body, request_id: request_id
          )
        end

        case status
        when 400, 422 then ValidationError.new(status, message, **common)
        when 401 then AuthenticationError.new(status, message, **common)
        when 403 then PermissionDeniedError.new(status, message, **common)
        when 404 then NotFoundError.new(status, message, **common)
        when 409 then ConflictError.new(status, message, **common)
        when 429 then RateLimitError.new(status, message, retry_after: retry_after_seconds(headers["retry-after"]), **common)
        else
          status >= 500 ? ServerError.new(status, message, **common) : MisarDevError.new(status, message, **common)
        end
      end

      # 204/empty → nil; JSON → decoded (string keys); anything else → the raw string.
      def self.decode_body(status, text)
        return nil if status == 204 || text.nil? || text.empty?

        JSON.parse(text)
      rescue JSON::ParserError
        text
      end

      # ── Requests ──────────────────────────────────────────────────────────

      # Send one request, retrying throttles and (for idempotent verbs)
      # transient failures.
      #
      # @return [Hash, Array, String, nil] decoded JSON, a raw string, or nil
      # @raise [MisarDevError]
      def request(method, path, query: nil, body: nil, headers: {})
        verb = method.to_s.upcase
        req = Request.new(
          method: verb,
          url: "#{@base_url}#{path}#{self.class.build_query(query)}",
          headers: headers_for("application/json", headers),
          body: encode_body(body),
          timeout: @timeout
        )

        attempt = 0
        loop do
          last = attempt >= @max_retries - 1
          begin
            res = @http.call(req)
          rescue MisarDevError
            raise
          rescue StandardError => e
            if !last && IDEMPOTENT.include?(verb)
              sleep(self.class.backoff(attempt))
              attempt += 1
              next
            end
            raise NetworkError, e.message.to_s.empty? ? "Network error" : e.message
          end

          decoded = self.class.decode_body(res.status, res.body)
          return decoded if res.status >= 200 && res.status < 300

          # Read the body BEFORE deciding to retry: a 429 from the rate limiter
          # and a 429 from a spent plan allowance share a status, and only the
          # first is worth retrying.
          error = self.class.error_for(res.status, res.headers, decoded, res.reason)
          raise error if error.is_a?(PlanLimitError)

          retryable = RETRYABLE.include?(res.status) && (res.status == 429 || IDEMPOTENT.include?(verb))
          raise error unless retryable && !last

          sleep(self.class.backoff(attempt, res.header("retry-after")))
          attempt += 1
        end
      end

      # Open a Server-Sent Events stream and yield each StreamEvent; returns an
      # Enumerator when no block is given.
      #
      # Never retried: a stream that fails mid-flight cannot be replayed without
      # duplicating what the caller already consumed. A
      # {type:"error", code:"plan_limit_exceeded", upgrade} frame is raised as a
      # PlanLimitError, exactly as the same refusal on a plain request would be.
      def stream(method, path, query: nil, body: nil, terminator: "[DONE]", headers: {}, &block)
        unless block
          return enum_for(:stream, method, path, query: query, body: body, terminator: terminator, headers: headers)
        end

        req = Request.new(
          method: method.to_s.upcase,
          url: "#{@base_url}#{path}#{self.class.build_query(query)}",
          headers: headers_for("text/event-stream", headers),
          body: encode_body(body),
          timeout: nil # a stream has no fixed duration
        )

        user_raised = false
        deliver = lambda do |event, res|
          # Other error frames are the stream's own business (the build stream
          # reports a failed step and carries on), so only the plan refusal —
          # which no amount of reading further will fix — is raised.
          raise self.class.error_for(402, res.headers, event.data) if self.class.plan_limit_body?(event.data)

          begin
            block.call(event)
          rescue Exception # rubocop:disable Lint/RescueException
            user_raised = true
            raise
          end
        end

        begin
          catch(:misardev_sse_done) do
            @http.stream(req) do |res|
              unless res.status >= 200 && res.status < 300
                decoded = self.class.decode_body(res.status, res.read_all)
                raise self.class.error_for(res.status, res.headers, decoded, res.reason)
              end

              parser = SSE.new(terminator)
              res.each_chunk do |chunk|
                parser.feed(chunk) { |event| deliver.call(event, res) }
                # Leave the connection rather than reading on past the terminator.
                throw :misardev_sse_done if parser.done?
              end
              parser.finish { |event| deliver.call(event, res) }
            end
          end
        rescue MisarDevError
          raise
        rescue StandardError => e
          raise if user_raised

          raise NetworkError, e.message.to_s.empty? ? "Network error" : e.message
        end
        nil
      end

      private

      def present(value)
        value.nil? || value.to_s.empty? ? nil : value.to_s
      end

      def encode_body(body)
        body.nil? ? nil : JSON.generate(body)
      end

      def headers_for(accept, extra)
        {
          "Authorization" => "Bearer #{@api_key}",
          "Accept" => accept,
          "Content-Type" => "application/json",
          "X-Misar-SDK" => "misardev-ruby/#{VERSION}"
        }.merge(@headers).merge(extra || {})
      end
    end
  end
end
