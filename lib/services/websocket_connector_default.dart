import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectAppWebSocket(Uri uri) {
  return WebSocketChannel.connect(uri);
}
