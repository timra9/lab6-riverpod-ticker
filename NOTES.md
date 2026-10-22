# Lab 6 Notes

## Part 2 - Model and stream provider

**Why is the feed behind its own `Provider` instead of being constructed inside `tickerProvider`?**
So it can be swapped without touching `tickerProvider`. Tests override it with `tickFeedProvider.overrideWithValue(TickFeed(symbols: ['BTC']))`, and the error demo builds it with `failAfter`. It also keeps one place that decides how the feed is created (dependency injection), and `tickerProvider` only describes what to do with it.

**What does `autoDispose` do when the user navigates away mid-stream?**
When nothing watches `tickerProvider` any more, Riverpod disposes it: the stream subscription is cancelled, the `async*` generator stops, and the cached state is thrown away. Coming back creates it again from scratch, so the user sees a fresh loading state instead of an old stream running in the background.

**What `AsyncValue` does `tickerProvider` hold during the 800 ms delay, and what is `hasValue` at that moment?**
`AsyncLoading`, with no previous value, so `hasValue` is `false` (`value` is `null`).

Checkpoint: `ref.listen(tickerProvider, ...)` printed a stream of `AsyncData<List<Tick>>` twice a second. The first `AsyncLoading` is only printed with `fireImmediately: true`, because `ref.listen` fires on changes and the provider already starts in `AsyncLoading`.

Note on Riverpod 3: by default a provider that fails is retried automatically, and while it retries its state is `AsyncLoading` (holding the error and the old value), so the error state never stays on screen. `tickerProvider` sets `retry: (retryCount, error) => null` to turn that off, because this lab retries manually with a button.

## Part 3 - Ticker UI with AsyncValue pattern matching

**3.3 - Diagnostic when the `AsyncLoading()` arm is removed (`flutter analyze`):**

```
error • The type 'AsyncValue<List<Tick>>' isn't exhaustively matched by the switch cases since it doesn't match the pattern 'AsyncLoading<List<Tick>>()'. Try adding a wildcard pattern or cases that match 'AsyncLoading<List<Tick>>()' • lib/ticker_page.dart:15:13 • non_exhaustive_switch_expression
```

It is a compile error, not a warning: because `AsyncValue` is sealed, the compiler knows every subtype and refuses to build until each state is handled.

**3.4 - Why must the `value: []` and `value: [final only]` arms come before the general `AsyncData` arm?**
A `switch` checks the arms from top to bottom and uses the first one that matches. `AsyncData(:final value)` matches every `AsyncData`, including empty and one-item lists, so if it were first the two specific arms would never run (the analyzer reports them as unreachable, already covered by a previous case).

Verified by overriding the feed with `TickFeed(symbols: const [])` (shows "No symbols subscribed"), `TickFeed(symbols: const ['BTC'])` (one centered row), and `TickFeed(failAfter: 5)` (shows "Error: Feed disconnected").

## Part 4 - Errors, retry, and preserving previous data

`failAfterProvider` is a `StateProvider`, which in Riverpod 3 is a legacy API, so it is imported from `package:flutter_riverpod/legacy.dart`. The two AppBar buttons ("Break feed" / "Fix feed") set it to `5` / `null`.

**4.3 - `refresh` vs `invalidate` in the `RefreshIndicator`**
Both keep the previous rows visible during the reload. In both cases the provider goes to `AsyncLoading` *with the old value* (`isRefreshing == true`), so the `AsyncValue(:final value?, isLoading: true)` arm shows the rows with a thin progress bar. The difference is what `onRefresh` gets back:
- `ref.refresh(tickerProvider.future)` rebuilds the provider immediately and returns the new `Future<List<Tick>>`, which completes when the first new ticks arrive. `RefreshIndicator.onRefresh` needs a `Future`, so its pull-to-refresh spinner stays until fresh data is actually on screen.
- `ref.invalidate(tickerProvider)` returns `void`; it only marks the provider dirty and it is rebuilt on the next read. There is nothing to await, so the pull spinner disappears at once while data is still loading.

The final code uses `ref.refresh(tickerProvider.future)`.

**4.4 - Reconnect vs first load**
Already handled by the arm order: after Retry the state is an `AsyncError` (or `AsyncLoading`) that still carries the old ticks, so it matches the banner arm or the progress-bar arm before it can reach `AsyncLoading()`. The full-screen spinner only shows on cold start, when there is no value yet. Checked: cold start shows the spinner; Break feed shows the progress bar over the rows, then the banner over dimmed rows; Retry keeps the rows and brings back live data.

**Difference between `isRefreshing` and `isReloading`:** both mean "loading while holding an old value", but `isRefreshing` is a reload the code asked for with `ref.refresh` / `ref.invalidate`, while `isReloading` is a rebuild caused by a dependency changing (here `tickFeedProvider` changing when `failAfterProvider` is toggled).
