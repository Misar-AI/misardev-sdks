# frozen_string_literal: true

require "json"

module MisarDev
  # One Server-Sent Event. +data+ is the JSON-decoded payload (string keys), or
  # the raw string when it is not JSON; +event+ and +id+ are the `event:` and
  # `id:` fields when the server sends them.
  StreamEvent = Struct.new(:event, :data, :id, keyword_init: true)

  module Core
    # Server-Sent Events parsing.
    #
    # Frames are separated by a blank line (\n\n or \r\n\r\n) and may span
    # several `data:` lines, which are joined with newlines per the SSE spec.
    # Comment lines (`:`) are keep-alives and are skipped. The terminator
    # payload — `[DONE]` on the OpenAI-compatible /v1/chat/completions stream —
    # ends iteration and is never yielded. A nil terminator reads to EOF.
    class SSE
      SEPARATOR = /\r?\n\r?\n/.freeze

      # Parse one complete frame (the text between blank lines).
      # @return [Hash] { event:, data:, id: } — data is nil when the frame had none
      def self.parse_frame(frame)
        event = nil
        id = nil
        data = []
        frame.split(/\r?\n/).each do |line|
          next if line.empty? || line.start_with?(":")

          idx = line.index(":")
          field = idx ? line[0...idx] : line
          value = idx ? line[(idx + 1)..] : ""
          value = value[1..] if value.start_with?(" ")
          case field
          when "data" then data << value
          when "event" then event = value
          when "id" then id = value
          end
        end
        { event: event, data: data.empty? ? nil : data.join("\n"), id: id }
      end

      # JSON-decode a payload when possible, else hand back the raw string.
      def self.decode(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        raw
      end

      def initialize(terminator = "[DONE]")
        @terminator = terminator
        @buffer = +""
        @done = false
      end

      # True once the terminator has been seen; stop reading.
      def done?
        @done
      end

      # Feed a chunk; yields each StreamEvent completed by it.
      def feed(chunk)
        return if @done

        @buffer << chunk
        while (m = SEPARATOR.match(@buffer))
          frame = @buffer[0...m.begin(0)]
          @buffer = @buffer[m.end(0)..]
          event = to_event(frame)
          return if @done
          next if event.nil?

          yield event
        end
      end

      # Flush a final frame the server never terminated with a blank line.
      def finish
        return if @done

        event = to_event(@buffer)
        @buffer = +""
        yield event if event && !@done
      end

      private

      def to_event(frame)
        parsed = self.class.parse_frame(frame)
        return nil if parsed[:data].nil?

        if @terminator && parsed[:data].strip == @terminator
          @done = true
          return nil
        end
        StreamEvent.new(event: parsed[:event], data: self.class.decode(parsed[:data]), id: parsed[:id])
      end
    end
  end
end
