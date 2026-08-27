import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectAppWebSocket(Uri uri) {
  return IOWebSocketChannel.connect(
    uri.toString(),
    connectTimeout: const Duration(seconds: 12),
    pingInterval: const Duration(seconds: 25),
  );
}
