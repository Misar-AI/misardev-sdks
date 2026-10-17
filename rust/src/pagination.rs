//! Offset pagination.
//!
//! List endpoints that take `limit` / `offset` (templates, gallery, API keys…)
//! return one page at a time. [`paginate`] walks every page: it calls
//! `fetch_page(offset, limit)`, yields each item, and stops on a short page.
//! Items are read from the response itself when it is an array, otherwise from
//! its first array-valued field (`templates`, `items`, `keys`, …).

use std::collections::VecDeque;
use std::future::Future;
use std::pin::Pin;

use futures::Stream;
use serde_json::Value;

use crate::error::MisarDevError;

/// The items of one page: the page itself when it is an array, otherwise its
/// first array-valued field, otherwise nothing.
pub fn items_of(page: Value) -> Vec<Value> {
    match page {
        Value::Array(items) => items,
        Value::Object(map) => map
            .into_iter()
            .find_map(|(_, v)| match v {
                Value::Array(items) => Some(items),
                _ => None,
            })
            .unwrap_or_default(),
        _ => Vec::new(),
    }
}

/// Options for [`paginate`].
#[derive(Debug, Clone, Copy)]
pub struct PaginateOptions {
    /// The `limit` requested per page. Default 50.
    pub page_size: usize,
    /// Stop after this many items. Default: no cap.
    pub max_items: Option<usize>,
}

impl Default for PaginateOptions {
    fn default() -> Self {
        Self {
            page_size: 50,
            max_items: None,
        }
    }
}

struct State<F> {
    fetch: F,
    page_size: usize,
    max: usize,
    offset: usize,
    yielded: usize,
    buf: VecDeque<Value>,
    last: bool,
    failed: bool,
}

/// Walk an offset-paginated endpoint as a stream of items.
///
/// ```no_run
/// # async fn run(dev: misardev::MisarDev) -> Result<(), misardev::MisarDevError> {
/// use futures::StreamExt;
/// use serde_json::json;
///
/// let mut templates = misardev::paginate(
///     |offset, limit| dev.templates().list(Some(json!({ "offset": offset, "limit": limit }))),
///     misardev::PaginateOptions::default(),
/// );
/// while let Some(t) = templates.next().await {
///     println!("{}", t?);
/// }
/// # Ok(()) }
/// ```
pub fn paginate<'a, F, Fut>(
    fetch: F,
    options: PaginateOptions,
) -> Pin<Box<dyn Stream<Item = Result<Value, MisarDevError>> + Send + 'a>>
where
    F: FnMut(usize, usize) -> Fut + Send + 'a,
    Fut: Future<Output = Result<Value, MisarDevError>> + Send + 'a,
{
    let state = State {
        fetch,
        page_size: options.page_size.max(1),
        max: options.max_items.unwrap_or(usize::MAX),
        offset: 0,
        yielded: 0,
        buf: VecDeque::new(),
        last: false,
        failed: false,
    };
    Box::pin(futures::stream::unfold(state, |mut st| async move {
        if st.failed || st.yielded >= st.max {
            return None;
        }
        while st.buf.is_empty() {
            if st.last {
                return None;
            }
            match (st.fetch)(st.offset, st.page_size).await {
                Ok(page) => {
                    let items = items_of(page);
                    st.offset += items.len();
                    st.last = items.len() < st.page_size;
                    if items.is_empty() {
                        return None;
                    }
                    st.buf.extend(items);
                }
                Err(e) => {
                    st.failed = true;
                    return Some((Err(e), st));
                }
            }
        }
        let item = st.buf.pop_front()?;
        st.yielded += 1;
        Some((Ok(item), st))
    }))
}
