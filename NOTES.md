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
