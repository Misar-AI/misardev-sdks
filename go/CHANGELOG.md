# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases are tagged
`go/vX.Y.Z` on https://github.com/Misar-AI/misardev-sdks.

## [1.1.0] — 2026-11-07

### Added

- The social API, generated from the route tree like everything else. New methods:
  - `dev.Posts`: `Create`, `CreateComment`, `Get`, `Like`, `List`, `ListComments`, `ListSaved`, `Save`, `ShareToDm`, `Unlike`, `Unsave`, `Update`
  - `dev.Comments`: `Delete`, `Like`, `Unlike`, `Update`
  - `dev.Feed`: `Following`, `ForYou`
  - `dev.Tags`: `Get`
  - `dev.Collections`: `AddPost`, `Create`, `Delete`, `List`, `RemovePost`, `Update`
  - `dev.Stories`: `Create`, `Delete`, `Get`, `ListMyPosts`, `ListViewers`, `MarkSeen`, `Reply`, `Tray`
  - `dev.Highlights`: `AddStory`, `Create`, `Delete`, `List`, `RemoveStory`, `Update`
  - `dev.CloseFriends`: `Add`, `List`, `Remove`
  - `dev.Dm`: `AcceptThread`, `CreateThread`, `DeclineThread`, `ListMessages`, `ListThreads`, `MarkThreadRead`, `SendMessage`, `UnreadCounts`
  - `dev.Social`: `DismissSuggestion`, `ListSuggestions`, `Relationship`
  - `dev.Profile`: `Block`, `Mute`, `Unblock`, `Unmute`
- Routes that had landed without reaching the manifest:
  - `dev.Domains`: `Checkout`, `CreateDnsRecord`, `DeleteDnsRecord`, `List`, `ListDnsRecords`, `Search`, `Update`
  - `dev.Projects`: `RecommendDomains`
- `dev.Search.Code` now takes the `cursor` and `type` query parameters the route already read.
- `dev.Profile`: `GetHighlight` — one profile highlight's stories, ready to play, read when its circle is opened. `ListHighlights` now answers the circles only (`id`, `title`, `coverUrl`, `createdAt`, `storyCount`, `closeFriends`), without stories.
- The surface is now 31 resources, 180 methods and 3 streams (183 operations).

### Notes

- `dev.Posts.List`, `dev.Posts.Get`, `dev.Posts.ListComments`, `dev.Tags.Get` and `dev.Feed.ForYou` are public reads: they answer without a key, and a key only adds viewer flags and filtering.
- Not exposed on purpose: `POST /api/media/upload-url` (the signed URL needs a raw browser `PUT`) and `POST /api/posts/{id}/view` (a cookie-deduplicated page beacon).

## [1.0.0] — 2026-10-16

First release under the `misardev` name, at `github.com/Misar-AI/misardev-sdks/go`.
It replaces the previous unpublished hand-written `misardev-go` client, whose
types and method set it does not keep.

### Added

- Every route in `sdks/manifest.json` — 21 resources, 106 methods and 3
  Server-Sent Events streams (109 operations) — generated from the API's own
  route tree, each method taking a `context.Context` first and returning the
  decoded JSON.
- `NewClient(apiKey, opts...)` with `MISARDEV_API_KEY` / `MISARDEV_BASE_URL`
  fallbacks and `WithBaseURL`, `WithMaxRetries`, `WithTimeout`,
  `WithHTTPClient`, `WithHeader` options; `WithCallHeader` per call.
- Typed errors embedding `*APIError`: `ValidationError`, `AuthenticationError`,
  `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`,
  `ServerError`, `NetworkError`, and `PlanLimitError` carrying the server's full
  upgrade offer with `UpgradeURL`, `Feature`, `CurrentPlan`, `RecommendedPlan`
  and `RetryAfter`.
- Retries for throttles (any verb) and transient failures (idempotent verbs
  only), honouring `Retry-After` and never retrying a plan refusal.
- SSE streaming via `*Stream` (`Next` / `Event` / `Err` / `Close`) for chat
  completions, the studio conversation and build progress.
- `Paginate` for offset-paginated list endpoints, and `As[T]` to convert a
  decoded response into your own type.
