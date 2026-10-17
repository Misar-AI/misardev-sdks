# frozen_string_literal: true

module MisarDev
  module Core
    # Offset pagination.
    #
    # List endpoints that take limit/offset (templates, gallery, API keys…)
    # return one page at a time. Pagination.paginate walks every page: it calls
    # the block with (offset, limit), yields each item, and stops on a short
    # page. Items are read from the response itself when it is an Array,
    # otherwise from its first Array-valued field (templates, items, keys, …).
    #
    #   dev.paginate { |offset, limit| dev.templates.list(offset: offset, limit: limit) }.each { |t| … }
    module Pagination
      module_function

      def items_of(page)
        return page if page.is_a?(Array)
        return page.values.find { |v| v.is_a?(Array) } || [] if page.is_a?(Hash)

        []
      end

      # @return [Enumerator] when no consumer block is given
      def paginate(page_size: 50, max_items: nil, fetch_page: nil, &consumer)
        raise ArgumentError, "fetch_page is required" if fetch_page.nil?
        return enum_for(:paginate, page_size: page_size, max_items: max_items, fetch_page: fetch_page) unless consumer

        offset = 0
        yielded = 0
        loop do
          break if max_items && yielded >= max_items

          items = items_of(fetch_page.call(offset, page_size))
          items.each do |item|
            return nil if max_items && yielded >= max_items

            consumer.call(item)
            yielded += 1
          end
          break if items.length < page_size

          offset += items.length
        end
        nil
      end
    end
  end
end
