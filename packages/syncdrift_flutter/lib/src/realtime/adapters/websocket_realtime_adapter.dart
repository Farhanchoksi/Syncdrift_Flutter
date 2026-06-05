import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../realtime_event.dart';
import '../realtime_adapter.dart';

/// A [RealtimeAdapter] that listens to push update events from a WebSocket stream.
class WebSocketRealtimeAdapter implements RealtimeAdapter {
  final String url;
  final StreamController<RealtimeEvent> _controller =
      StreamController<RealtimeEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  WebSocketRealtimeAdapter({required this.url});

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    if (_channel != null) {
      return;
    }

    final uri = Uri.parse(url);
    _channel = WebSocketChannel.connect(uri);

    _subscription = _channel!.stream.listen(
      (dynamic data) {
        try {
          final jsonMap = json.decode(data.toString()) as Map<String, dynamic>;
          final table = jsonMap['table'] as String;
          final eventType = jsonMap['event_type'] as String;
          final record = jsonMap['record'] as Map<String, dynamic>;
          final oldRecord = jsonMap['old_record'] as Map<String, dynamic>?;

          _controller.add(RealtimeEvent(
            table: table,
            eventType: eventType,
            record: record,
            oldRecord: oldRecord,
          ));
        } catch (e) {
          _controller.addError(
              StateError('WebSocket message parsing failed: $e. Msg: $data'));
        }
      },
      onError: (Object err) {
        _controller.addError(err);
      },
      onDone: () {
        disconnect();
      },
    );
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;
  }
}
