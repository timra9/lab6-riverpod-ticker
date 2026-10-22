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

## Part 5 - Tests

`flutter test` passes 6 tests: 2 provider tests and 4 widget tests, including `error after data shows banner over rows`, which uses a `StreamController`: it adds `sample`, checks the row is shown with no banner, then calls `addError` and checks that both the `MaterialBanner` and the `BTC` row are on screen.

Changes needed for Riverpod 3:
- `riverpod_test` could not be installed: it depends on Riverpod 2, so it conflicts with `flutter_riverpod` 3. It was not used by any test, so it was dropped.
- `Override` (the type in `harness`) moved to `package:flutter_riverpod/misc.dart`.
- In the first provider test, `container.read` alone does not keep an `autoDispose` provider alive, so it was disposed while loading ("disposed during loading state, yet no value could be emitted"). The test now holds a `container.listen` subscription, like the second test.

## Checkpoint questions

**1. Which three subtypes make `AsyncValue` sealed, and what does the analyzer report when a `switch` expression misses one?**
`AsyncData`, `AsyncLoading` and `AsyncError`. Missing one is a compile error, `non_exhaustive_switch_expression`: "The type 'AsyncValue<List<Tick>>' isn't exhaustively matched by the switch cases since it doesn't match the pattern 'AsyncLoading<List<Tick>>()'".

**2. When does `AsyncError.value` carry a non-null value, and when is it null?**
It is non-null when the provider had already produced data before the error: Riverpod copies the previous value into the error state (e.g. the feed emits ticks and then disconnects). It is null when the error happens before any data was ever emitted, e.g. the very first load fails (`Stream.error('boom')` in the tests).

**3. What is the difference between `ref.refresh(provider)`, `ref.refresh(provider.future)` and `ref.invalidate(provider)`?**
- `ref.refresh(provider)` throws away the current state, rebuilds the provider immediately, and returns the new `AsyncValue` (usually loading, with the old value kept).
- `ref.refresh(provider.future)` does the same rebuild but returns the `Future` of the new value, so it can be awaited, e.g. in `RefreshIndicator.onRefresh`, which waits until new data arrives.
- `ref.invalidate(provider)` only marks the provider as dirty and returns `void`; it is rebuilt lazily the next time it is read or listened to. It is the one to use in button callbacks where you do not need a result.

**4. Why does `AsyncValue(:final value?, isLoading: true)` need to sit above `AsyncData(:final value)`?**
During a refresh Riverpod keeps the old data, and the state can still be an `AsyncData` with `isLoading == true` (seen while testing: `invalidate` gives `AsyncData loading=true refreshing=true`). The first matching arm wins, so if `AsyncData(:final value)` came first it would catch that state, and the progress bar would never be shown. The more specific arm must come first.

**5. Give one reason to prefer `switch` expressions over `.when(...)` for `AsyncValue`, and one situation where `.when` is still convenient.**
`switch` lets you match on more than the state: on the content (`value: []`, `value: [final only]`), on flags (`isLoading: true`), and on whether old data exists (`value?`), and the order of arms gives clear priorities, all checked for exhaustiveness by the compiler. `.when` is still convenient for a simple loading / data / error widget written inline, because its defaults (`skipLoadingOnRefresh`, `skipLoadingOnReload`) already keep showing old data during a refresh without writing extra arms.
