import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tick.dart';
import '../services/tick_feed.dart';

final tickFeedProvider = Provider<TickFeed>((ref) => TickFeed());

final tickerProvider = StreamProvider.autoDispose<List<Tick>>((ref) {
  return ref.watch(tickFeedProvider).watch();
});
