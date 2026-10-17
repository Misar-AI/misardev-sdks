package misardev

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
)

// SSEEvent is one Server-Sent Events frame.
type SSEEvent struct {
	// Event is the `event:` name, empty when the server sent none.
	Event string
	// Data is the JSON-decoded `data:` payload, or the raw string when it is
	// not JSON. Multiple data lines are joined with "\n".
	Data any
	// ID is the `id:` field, empty when absent.
	ID string
}

// Stream iterates the events of a text/event-stream response:
//
//	s, err := dev.Chat.CompletionsStream(ctx, body)
//	if err != nil { ... }
//	defer s.Close()
//	for s.Next() {
//		ev := s.Event()
//		...
//	}
//	if err := s.Err(); err != nil { ... }
//
// The stream stops at its terminator (`[DONE]` for chat completions), which is
// never yielded. A frame carrying `code: "plan_limit_exceeded"` stops the
// stream with a *PlanLimitError from Err.
type Stream struct {
	resp       *http.Response
	reader     *bufio.Reader
	terminator string
	current    SSEEvent
	err        error
	done       bool
}

func newStream(resp *http.Response, terminator string) *Stream {
	return &Stream{resp: resp, reader: bufio.NewReader(resp.Body), terminator: terminator}
}

// Next advances to the next event. It returns false at the end of the stream
// or on error; check Err afterwards.
func (s *Stream) Next() bool {
	if s.done {
		return false
	}
	var (
		event, id string
		data      []string
		hasData   bool
	)
	for {
		line, err := s.reader.ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			s.finish(newNetworkError(err))
			return false
		}
		eof := err != nil
		line = strings.TrimRight(line, "\r\n")

		if line == "" {
			// A blank line ends the frame (or EOF flushes a trailing one).
			if hasData {
				if ok := s.emit(event, id, data); ok {
					if eof {
						s.finish(nil)
						// The event is still delivered; the next call ends.
						s.done = true
					}
					return true
				}
				return false
			}
			event, id, data, hasData = "", "", nil, false
			if eof {
				s.finish(nil)
				return false
			}
			continue
		}

		if !strings.HasPrefix(line, ":") {
			field, value := line, ""
			if i := strings.IndexByte(line, ':'); i >= 0 {
				field, value = line[:i], line[i+1:]
				value = strings.TrimPrefix(value, " ")
			}
			switch field {
			case "data":
				data = append(data, value)
				hasData = true
			case "event":
				event = value
			case "id":
				id = value
			}
		}

		if eof {
			if hasData {
				if ok := s.emit(event, id, data); ok {
					s.finish(nil)
					s.done = true
					return true
				}
				return false
			}
			s.finish(nil)
			return false
		}
	}
}

// emit decodes a frame into s.current. It returns false (and ends the
// stream) on the terminator or a plan-limit frame.
func (s *Stream) emit(event, id string, data []string) bool {
	raw := strings.Join(data, "\n")
	if s.terminator != "" && strings.TrimSpace(raw) == s.terminator {
		s.finish(nil)
		return false
	}
	var decoded any = raw
	var v any
	if json.Unmarshal([]byte(raw), &v) == nil {
		decoded = v
	}
	if isPlanLimitBody(decoded) {
		s.finish(errorFor(402, s.resp.Header, decoded, ""))
		return false
	}
	s.current = SSEEvent{Event: event, Data: decoded, ID: id}
	return true
}

func (s *Stream) finish(err error) {
	if s.err == nil {
		s.err = err
	}
	s.done = true
	s.resp.Body.Close()
}

// Event is the event Next just advanced to.
func (s *Stream) Event() SSEEvent { return s.current }

// Err is the error that ended the stream, or nil when it ended cleanly.
func (s *Stream) Err() error { return s.err }

// Close releases the connection. Safe to call more than once.
func (s *Stream) Close() error {
	s.done = true
	return s.resp.Body.Close()
}
