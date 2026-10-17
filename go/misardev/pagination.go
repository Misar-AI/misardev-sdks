package misardev

import (
	"context"
	"sort"
)

// PageFunc fetches one page of a list endpoint at the given offset and limit.
type PageFunc func(ctx context.Context, offset, limit int) (any, error)

// PaginateOptions configures [Paginate].
type PaginateOptions struct {
	// PageSize is the limit requested per page (default 50).
	PageSize int
	// MaxItems stops after this many items (0 means no cap).
	MaxItems int
}

// Pager walks every page of an offset-paginated list endpoint:
//
//	p := misardev.Paginate(ctx, func(ctx context.Context, offset, limit int) (any, error) {
//		return dev.Templates.List(ctx, misardev.Query{"offset": offset, "limit": limit})
//	}, misardev.PaginateOptions{})
//	for p.Next() {
//		fmt.Println(p.Item())
//	}
//	if err := p.Err(); err != nil { ... }
//
// Items are read from the page itself when it is a JSON array, otherwise from
// its first array-valued field (templates, items, keys, …). It stops on a
// short page.
type Pager struct {
	ctx      context.Context
	fetch    PageFunc
	pageSize int
	maxItems int

	offset  int
	yielded int
	buf     []any
	current any
	err     error
	last    bool
}

// Paginate returns a [Pager] over fetch.
func Paginate(ctx context.Context, fetch PageFunc, opts PaginateOptions) *Pager {
	if ctx == nil {
		ctx = context.Background()
	}
	size := opts.PageSize
	if size <= 0 {
		size = 50
	}
	return &Pager{ctx: ctx, fetch: fetch, pageSize: size, maxItems: opts.MaxItems}
}

// Next advances to the next item, fetching the next page when needed.
func (p *Pager) Next() bool {
	if p.err != nil || (p.maxItems > 0 && p.yielded >= p.maxItems) {
		return false
	}
	for len(p.buf) == 0 {
		if p.last {
			return false
		}
		page, err := p.fetch(p.ctx, p.offset, p.pageSize)
		if err != nil {
			p.err = err
			return false
		}
		items := ItemsOf(page)
		p.offset += len(items)
		if len(items) < p.pageSize {
			p.last = true
		}
		p.buf = items
		if len(items) == 0 {
			return false
		}
	}
	p.current, p.buf = p.buf[0], p.buf[1:]
	p.yielded++
	return true
}

// Item is the item Next just advanced to.
func (p *Pager) Item() any { return p.current }

// Err is the error that stopped the walk, if any.
func (p *Pager) Err() error { return p.err }

// ItemsOf returns the items of one page: the page itself when it is an array,
// otherwise its first array-valued field (in key order), otherwise nil.
func ItemsOf(page any) []any {
	switch v := page.(type) {
	case []any:
		return v
	case map[string]any:
		keys := make([]string, 0, len(v))
		for k := range v {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			if arr, ok := v[k].([]any); ok {
				return arr
			}
		}
	}
	return nil
}
