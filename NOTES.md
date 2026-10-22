# Lab 6 Notes

## Part 2 - Model and stream provider

**Why is the feed behind its own `Provider` instead of being constructed inside `tickerProvider`?**
So it can be swapped without touching `tickerProvider`. Tests override it with `tickFeedProvider.overrideWithValue(TickFeed(symbols: ['BTC']))`, and the error demo builds it with `failAfter`. It also keeps one place that decides how the feed is created (dependency injection), and `tickerProvider` only describes what to do with it.

**What does `autoDispose` do when the user navigates away mid-stream?**
When nothing watches `tickerProvider` any more, Riverpod disposes it: the stream subscription is cancelled, the `async*` generator stops, and the cached state is thrown away. Coming back creates it again from scratch, so the user sees a fresh loading state instead of an old stream running in the background.

**What `AsyncValue` does `tickerProvider` hold during the 800 ms delay, and what is `hasValue` at that moment?**
`AsyncLoading`, with no previous value, so `hasValue` is `false` (`value` is `null`).

Checkpoint: `ref.listen(tickerProvider, ...)` printed a stream of `AsyncData<List<Tick>>` twice a second. The first `AsyncLoading` is only printed with `fireImmediately: true`, because `ref.listen` fires on changes and the provider already starts in `AsyncLoading`.
