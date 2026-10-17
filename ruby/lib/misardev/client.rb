# frozen_string_literal: true

require_relative "core/transport"
require_relative "core/pagination"
require_relative "generated/resources"

module MisarDev
  # The MisarDev API client.
  #
  # Every resource (projects, templates, chat, …) is generated from the API's
  # route tree, so it always matches what the server exposes. The client
  # authenticates with your account API key (mdk_…) and nothing else.
  #
  #   dev = MisarDev::Client.new(ENV["MISARDEV_API_KEY"])
  #   dev.projects.list
  class Client
    include Generated::Resources

    # The underlying transport, for routes the SDK does not wrap yet.
    attr_reader :transport

    # @param api_key [String, nil] falls back to MISARDEV_API_KEY
    # @param base_url [String, nil] defaults to MISARDEV_BASE_URL, else https://api.misar.io/dev
    # @param max_retries [Integer] total attempts for a retryable failure
    # @param timeout [Numeric] per-attempt timeout in seconds; streams have none
    # @param http_client [#call, #stream] inject the HTTP layer (tests, proxies)
    # @param headers [Hash] extra headers sent with every request
    def initialize(api_key = nil, base_url: nil, max_retries: 3, timeout: 60, http_client: nil, headers: {})
      @transport = Core::Transport.new(
        api_key,
        base_url: base_url, max_retries: max_retries, timeout: timeout,
        http_client: http_client, headers: headers
      )
      init_resources(@transport)
    end

    def base_url
      @transport.base_url
    end

    def inspect
      "#<#{self.class.name} base_url=#{base_url.inspect}>"
    end

    # Call any route directly: dev.request("GET", "/projects", query: { limit: 5 })
    def request(method, path, query: nil, body: nil, headers: {})
      @transport.request(method, path, query: query, body: body, headers: headers)
    end

    # Open any SSE route directly. Yields StreamEvents, or returns an Enumerator.
    def stream(method, path, query: nil, body: nil, terminator: "[DONE]", headers: {}, &block)
      @transport.stream(method, path, query: query, body: body, terminator: terminator, headers: headers, &block)
    end

    # Walk every page of an offset-paginated list. The block fetches one page
    # given (offset, limit); returns an Enumerator over the items.
    #
    #   dev.paginate { |offset, limit| dev.templates.list(offset: offset, limit: limit) }.each { |t| … }
    def paginate(page_size: 50, max_items: nil, &fetch_page)
      Core::Pagination.paginate(page_size: page_size, max_items: max_items, fetch_page: fetch_page)
    end
  end
end
