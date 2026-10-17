# frozen_string_literal: true

require "net/http"
require "uri"

module MisarDev
  module Core
    # One outgoing request, as handed to an HTTP client. +timeout+ is seconds
    # per attempt, or nil for a stream (no overall limit).
    Request = Struct.new(:method, :url, :headers, :body, :timeout, keyword_init: true)

    # A complete response. Header names are lower-cased.
    Response = Struct.new(:status, :headers, :body, :reason, keyword_init: true) do
      def header(name)
        (headers || {})[name.to_s.downcase]
      end
    end

    # A response whose body arrives in pieces: status and headers up front,
    # #each_chunk yields the body as it is read off the wire.
    class StreamResponse
      attr_reader :status, :headers, :reason

      def initialize(status:, headers:, reason: "", &chunks)
        @status = status
        @headers = headers
        @reason = reason
        @chunks = chunks
      end

      def header(name)
        (headers || {})[name.to_s.downcase]
      end

      def each_chunk(&block)
        @chunks.call(&block)
      end

      def read_all
        out = +""
        each_chunk { |c| out << c }
        out
      end
    end

    # The default HTTP client: stdlib net/http, nothing else.
    #
    # Pass any object with the same two methods as +http_client:+ to the client
    # (tests, proxies). Raise any StandardError when no HTTP answer was received;
    # the transport turns it into a NetworkError. A non-2xx status is not an
    # exception at this layer — return it.
    class NetHttpClient
      # Idle time allowed between two reads of a stream.
      STREAM_READ_TIMEOUT = 300

      def initialize(open_timeout: 10)
        @open_timeout = open_timeout
      end

      # @return [Response]
      def call(request)
        uri = URI.parse(request.url)
        start(uri, request.timeout) do |http|
          res = http.request(build(uri, request))
          Response.new(status: res.code.to_i, headers: headers_of(res), body: res.body.to_s, reason: res.message.to_s)
        end
      end

      # Yields one StreamResponse; the connection is closed when the block returns.
      def stream(request)
        uri = URI.parse(request.url)
        start(uri, request.timeout || STREAM_READ_TIMEOUT) do |http|
          http.request(build(uri, request)) do |res|
            yield(StreamResponse.new(status: res.code.to_i, headers: headers_of(res), reason: res.message.to_s) do |&blk|
              res.read_body(&blk)
            end)
          end
        end
      end

      private

      def start(uri, timeout, &block)
        Net::HTTP.start(
          uri.host, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: @open_timeout,
          read_timeout: timeout,
          write_timeout: timeout,
          &block
        )
      end

      def build(uri, request)
        req = Net::HTTPGenericRequest.new(
          request.method, !request.body.nil?, request.method != "HEAD", uri.request_uri, request.headers
        )
        req.body = request.body unless request.body.nil?
        req
      end

      def headers_of(res)
        out = {}
        res.each_header { |k, v| out[k.downcase] = v }
        out
      end
    end
  end
end
