import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketManager {
  WebSocketChannel? _webSocketChannel;
  void Function(dynamic message)? onMessage;
  bool reconnect = false;
  String strUrl = "";

  WebSocketManager() {
    reconnect = false;
    strUrl = "";
  }

  initWebSocket(String url, {Iterable<String>? protocols}) {
    strUrl = url;
    try {
      _webSocketChannel = WebSocketChannel.connect(Uri.parse(url), protocols: protocols);

      _webSocketChannel!.stream.listen(
        (event) {
          try {
            onMessage!.call(const JsonDecoder().convert(event));
          } catch (e) {
            return;
          }
        },
        onDone: () {
          if (reconnect) {
            close();
            initWebSocket(strUrl);
          }
        },
        onError: (err) {
          close();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> close() async {
    try {
      await _webSocketChannel!.sink.close();
      _webSocketChannel = null;
    } catch (e) {
      print(e.toString());
    }
  }

  sendMessage(Map<dynamic, dynamic> requestMap) {
    try {
      _webSocketChannel!.sink.add(const JsonEncoder().convert(requestMap));
    } catch (e) {
      print(e.toString());
    }
  }

  startSubscription() {
    var request = {};
    request["type"] = "connection_init";
    sendMessage(request);
  }

  stopSubscription(String subscriptionId) {
    var request = {};
    request["type"] = "stop";
    request["id"] = subscriptionId;
    sendMessage(request);
  }
}