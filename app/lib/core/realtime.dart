import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api.dart';

/// Live chat events from the server: new messages, typing and read receipts.
abstract class Realtime {
  Stream<Map<String, dynamic>> get events;
}

/// No live events (tests, or before sign-in). Screens still work by refreshing.
class NoRealtime implements Realtime {
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
}

/// One websocket per signed-in user, reconnecting after drops.
class SocketRealtime implements Realtime {
  SocketRealtime(this.api);
  final ApiClient api;
  final _out = StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _ch;
  String? _token;
  Timer? _retry;
  int _attempt = 0;

  @override
  Stream<Map<String, dynamic>> get events {
    _ensure();
    return _out.stream;
  }

  void _ensure() {
    if (api.token == null) return _close();
    if (_ch != null && _token == api.token) return;
    _close();
    _token = api.token;
    final base = api.baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final ch = WebSocketChannel.connect(Uri.parse('$base/ws?token=${Uri.encodeComponent(_token!)}'));
    _ch = ch;
    ch.stream.listen(
      (data) {
        _attempt = 0;
        try {
          final e = jsonDecode(data as String);
          if (e is Map<String, dynamic>) _out.add(e);
        } catch (_) {}
      },
      onDone: () => _drop(ch),
      onError: (_) => _drop(ch),
      cancelOnError: true,
    );
  }

  void _drop(WebSocketChannel ch) {
    if (_ch != ch) return;
    _ch = null;
    _retry?.cancel();
    final wait = Duration(seconds: [1, 2, 5, 10, 30][_attempt.clamp(0, 4)]);
    _attempt++;
    _retry = Timer(wait, () {
      if (_out.hasListener) _ensure();
    });
  }

  void _close() {
    _retry?.cancel();
    _ch?.sink.close();
    _ch = null;
    _token = null;
  }
}
