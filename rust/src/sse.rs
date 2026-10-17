//! Server-Sent Events parsing.
//!
//! Frames are separated by a blank line (`\n\n` or `\r\n\r\n`) and may span
//! several `data:` lines, which are joined with newlines per the SSE spec.
//! Comment lines (`:`) are keep-alives and are skipped. The terminator payload
//! — `[DONE]` on the OpenAI-compatible `/v1/chat/completions` stream — ends the
//! stream and is never yielded.

use std::pin::Pin;

use futures::{Stream, StreamExt};
use reqwest::header::HeaderMap;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::{error_for, is_plan_limit_body, MisarDevError};

/// One Server-Sent Event.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SseEvent {
    /// The `event:` name, when the server sends one.
    pub event: Option<String>,
    /// JSON-decoded `data:` payload, or `Value::String` when it is not JSON.
    pub data: Value,
    /// The `id:` field, when present.
    pub id: Option<String>,
}

/// A boxed stream of events, as every streaming method returns.
pub type EventStream = Pin<Box<dyn Stream<Item = Result<SseEvent, MisarDevError>> + Send>>;

/// The fields of one frame, before decoding.
#[derive(Debug, Default, PartialEq)]
pub struct RawFrame {
    pub event: Option<String>,
    pub data: Option<String>,
    pub id: Option<String>,
}

/// Parse one complete frame (the text between blank lines).
pub fn parse_frame(frame: &str) -> RawFrame {
    let mut out = RawFrame::default();
    let mut data: Vec<&str> = Vec::new();
    for line in frame.split('\n') {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.is_empty() || line.starts_with(':') {
            continue;
        }
        let (field, value) = match line.find(':') {
            Some(i) => {
                let v = &line[i + 1..];
                (&line[..i], v.strip_prefix(' ').unwrap_or(v))
            }
            None => (line, ""),
        };
        match field {
            "data" => data.push(value),
            "event" => out.event = Some(value.to_owned()),
            "id" => out.id = Some(value.to_owned()),
            _ => {}
        }
    }
    if !data.is_empty() {
        out.data = Some(data.join("\n"));
    }
    out
}

/// Find the end of the first complete frame: (frame length, bytes consumed
/// including the blank-line separator).
fn frame_boundary(buf: &[u8]) -> Option<(usize, usize)> {
    let mut i = 0;
    while i < buf.len() {
        if buf[i] == b'\n' {
            let mut j = i + 1;
            if j < buf.len() && buf[j] == b'\r' {
                j += 1;
            }
            if j < buf.len() && buf[j] == b'\n' {
                return Some((i, j + 1));
            }
        }
        i += 1;
    }
    None
}

/// What a decoded frame means for the stream.
enum Step {
    Yield(SseEvent),
    Stop,
    Fail(MisarDevError),
    Skip,
}

fn decide(raw: RawFrame, terminator: Option<&str>, headers: &HeaderMap) -> Step {
    let Some(data) = raw.data else {
        return Step::Skip;
    };
    if terminator.is_some_and(|t| data.trim() == t) {
        return Step::Stop;
    }
    let value = serde_json::from_str::<Value>(&data).unwrap_or(Value::String(data));
    // Other error frames are the stream's own business (the build stream
    // reports a failed step and carries on), so only the plan refusal — which
    // no amount of reading further will fix — is raised.
    if is_plan_limit_body(&value) {
        return Step::Fail(error_for(402, headers, value, ""));
    }
    Step::Yield(SseEvent {
        event: raw.event,
        data: value,
        id: raw.id,
    })
}

struct State<S> {
    bytes: Pin<Box<S>>,
    buf: Vec<u8>,
    terminator: Option<String>,
    headers: HeaderMap,
    done: bool,
}

/// Turn a byte stream into SSE events. Used for every streaming response.
pub fn events<S, B, E>(bytes: S, terminator: Option<String>, headers: HeaderMap) -> EventStream
where
    S: Stream<Item = Result<B, E>> + Send + 'static,
    B: AsRef<[u8]>,
    E: Into<MisarDevError>,
{
    let state = State {
        bytes: Box::pin(bytes),
        buf: Vec::new(),
        terminator,
        headers,
        done: false,
    };
    Box::pin(futures::stream::unfold(state, |mut st| async move {
        if st.done {
            return None;
        }
        loop {
            // Serve anything already buffered before reading more.
            if let Some((len, consumed)) = frame_boundary(&st.buf) {
                let frame = String::from_utf8_lossy(&st.buf[..len]).into_owned();
                st.buf.drain(..consumed);
                match decide(parse_frame(&frame), st.terminator.as_deref(), &st.headers) {
                    Step::Yield(ev) => return Some((Ok(ev), st)),
                    Step::Stop => return None,
                    Step::Fail(e) => {
                        st.done = true;
                        return Some((Err(e), st));
                    }
                    Step::Skip => continue,
                }
            }
            match st.bytes.next().await {
                Some(Ok(chunk)) => st.buf.extend_from_slice(chunk.as_ref()),
                Some(Err(e)) => {
                    st.done = true;
                    return Some((Err(e.into()), st));
                }
                None => {
                    // EOF: flush a final unterminated frame.
                    st.done = true;
                    if st.buf.iter().all(u8::is_ascii_whitespace) {
                        return None;
                    }
                    let frame = String::from_utf8_lossy(&st.buf).into_owned();
                    st.buf.clear();
                    return match decide(parse_frame(&frame), st.terminator.as_deref(), &st.headers)
                    {
                        Step::Yield(ev) => Some((Ok(ev), st)),
                        Step::Fail(e) => Some((Err(e), st)),
                        Step::Stop | Step::Skip => None,
                    };
                }
            }
        }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_fields() {
        let f = parse_frame("event: step\r\nid: 7\r\ndata:  two spaces\r\ndata:x\r\n: comment");
        assert_eq!(f.event.as_deref(), Some("step"));
        assert_eq!(f.id.as_deref(), Some("7"));
        assert_eq!(f.data.as_deref(), Some(" two spaces\nx"));
        assert_eq!(parse_frame(": only a comment").data, None);
    }

    #[test]
    fn finds_both_separators() {
        assert_eq!(frame_boundary(b"data: a\n\nrest"), Some((7, 9)));
        assert_eq!(frame_boundary(b"data: a\r\n\r\nrest"), Some((8, 11)));
        assert_eq!(frame_boundary(b"data: a\n"), None);
    }
}
