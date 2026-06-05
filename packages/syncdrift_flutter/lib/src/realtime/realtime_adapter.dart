import 'realtime_event.dart';

/// Contract representing a subscription feed of remote database mutations.
abstract class RealtimeAdapter {
  /// Stream of real-time database mutations.
  Stream<RealtimeEvent> get events;

  /// Establishes the real-time subscription channel connection.
  Future<void> connect();

  /// Closes the subscription channel and cancels subscriptions.
  Future<void> disconnect();
}
