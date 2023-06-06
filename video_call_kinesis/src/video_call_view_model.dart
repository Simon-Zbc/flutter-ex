import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import 'kvs_repository.dart';
import 'web_socket_manager.dart';
import 'video_call_chat_message.dart';

class VideoCallViewModel extends ChangeNotifier {
  String selfId = "";
  bool isMaster;
  bool isHangUp = false;
  bool micOn = true;
  bool screenShare = false;
  bool cameraOn = true;
  bool chatOn = false;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final TextEditingController textController = TextEditingController();
  List<RemoteViews> remoteViewList = <RemoteViews>[];
  List<VideoCallChatMessage> messageList = <VideoCallChatMessage>[];
  Map<String, List> _iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.kinesisvideo.${Constants.AWS_REGION}.amazonaws.com:443'
        ]
      },
    ]
  };
  final Map<String, dynamic> mediaConstraints = {
    'audio': true,
    'video': {
      'mandatory': {
        // 'minWidth': '640',
        // 'minHeight': '480',
        'minFrameRate': '30',
      },
      'facingMode': 'user', // front camera
      // 'facingMode': 'environment', // back camera
      'optional': [],
    },
    'echoCancellation': true,
    'echoCancellationType': 'system',
    'noiseSuppression': true,
  };
  final Map<String, dynamic> mediaConstraintsScreen = {
    'audio': true,
    'video': true,
  };
  final Map<String, dynamic> offerSdpConstraints = {
    "mandatory": {
      "OfferToReceiveAudio": true,
      "OfferToReceiveVideo": true,
    },
    "optional": [],
  };

  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  WebSocketManager _webSocketManager = new WebSocketManager();
  MediaStream? localStream;
  MediaStream? remoteStream;
  List<MediaStream> remoteStreams = <MediaStream>[];
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  RTCRtpSender? rtpSender;
  Map<String, RTCPeerConnection> peerConnectionByClientId = Map();
  Map<String, RTCDataChannel> dataChannelByClientId = Map();
  List<RTCIceCandidate> iceCandidateByClientId = [];
  var heartbeatPeriod = const Duration(seconds: 180);
  Timer? heartbeatTimer;

  VideoCallViewModel(this.isMaster) {
    _init();
  }

  Future<void> _init() async {
    _initRenderers();
    await _kvsInit();
    if (isMaster) {
      await startMaster();
    } else {
      await startViewer();
    }
  }

  /// Initialize RTCVideoRenderer
  _initRenderers() async {
    await localRenderer.initialize();
  }

  /// Initialize kinesis video stream and webSocket
  Future<void> _kvsInit() async {
    // TODO get account name as clientId or selfId
    Uuid uuid = Uuid();
    selfId = uuid.v1();
    // SharedPreferences prefs = await SharedPreferences.getInstance();
    // prefs.setString('account', uuid.v1());
    // selfId = prefs.getString('account');

    String wssEndpoint =
        await KvsRepository.getWssEndpoint(isMaster, selfId, _iceServers);
    String url = KvsRepository.getSignedURL(wssEndpoint);
    _webSocketManager.reconnect = !isHangUp;
    _webSocketManager.onMessage = ((message) {
      onMessage(message);
    });
    _webSocketManager.initWebSocket(url);

    // TODO send heartbeat to signaling server(timeout 10min)
    heartbeatTimer = new Timer.periodic(heartbeatPeriod, (timer) {
      if (isHangUp) {
        heartbeatTimer!.cancel();
      } else {
        sendMessage(Constants.KINESIS_VIDEO_HEARTBEAT,
            _encoder.convert("Heartbeat"), selfId);
        print("VideoCallViewModel connect heartbeat...");
      }
    });
  }

  /// Send json data
  void sendMessage(
      String action, String messagePayload, String recipientClientId) {
    var request = Map();
    request["action"] = action;
    request["messagePayload"] = base64Encode(utf8.encode(messagePayload));
    request["recipientClientId"] = recipientClientId;
    _webSocketManager.sendMessage(request);
  }

  /// Close webSocket and cancel heartbeat timer
  close() async {
    if (heartbeatTimer != null) {
      heartbeatTimer!.cancel();
    }
    sendMessage(Constants.RECONNECT_ICE_SERVER,
        _encoder.convert("Reset ice server"), selfId);
    sendMessage(
        Constants.GO_AWAY, _encoder.convert("Close connection"), selfId);
    await _webSocketManager.close();
    // TODO delete the created signaling channel
    if (isMaster) {
      await KvsRepository.deleteSignalingChannel();
    }
    notifyListeners();
  }

  /// Switch camera
  void switchCamera() {
    Helper.switchCamera(localStream!.getVideoTracks()[0]);
    notifyListeners();
  }

  /// Mute mic
  void muteMic() {
    micOn = !micOn;
    bool enabled = localStream!.getAudioTracks()[0].enabled;
    localStream!.getAudioTracks()[0].enabled = !enabled;
    notifyListeners();
  }

  /// Turn on/off camera
  void turnCamera() {
    cameraOn = !cameraOn;
    // TODO
    notifyListeners();
  }

  /// Turn on/off message chat
  void turnMessage() {
    chatOn = !chatOn;
    notifyListeners();
  }

  /// Open mediaStream
  Future<void> startMaster() async {
    localStream = await createStream(screenShare);
    localStream!.onRemoveTrack = (track) {
      print("VideoCallViewModel startMaster onRemoveTrack");
      if (track.kind == 'video') {
        if (!isHangUp) {
          screenShare = !screenShare;
          changeLocalStream();
        }
      }
    };
    notifyListeners();
  }

  /// Close mediaStream and clear peerConnection and dataChannel
  void stopMaster() {
    if (null != localStream) {
      localStream!.getTracks().forEach((track) {
        track.stop();
        // localStream!.removeTrack(track);
      });
      localStream!.dispose();
    }

    remoteStreams.forEach((stream) {
      stream.getTracks().forEach((track) {
        track.stop();
        // stream.removeTrack(track);
      });
    });
    remoteStreams.clear();

    for (String client in dataChannelByClientId.keys) {
      if (dataChannelByClientId[client] != null) {
        dataChannelByClientId[client]!.close();
      }
    }

    for (String client in peerConnectionByClientId.keys) {
      if (peerConnectionByClientId[client] != null) {
        // peerConnectionByClientId[client]!.removeTrack(rtpSender!);
        // peerConnectionByClientId[client]!.removeStream(localStream!);
        peerConnectionByClientId[client]!.close();
      }
    }
  }

  /// Open mediaStream and send offer
  Future<void> startViewer() async {
    localStream = await createStream(screenShare);
    localStream!.onRemoveTrack = (track) {
      print("VideoCallViewModel startViewer onRemoveTrack");
      if (track.kind == 'video') {
        if (!isHangUp) {
          screenShare = !screenShare;
          changeLocalStream();
        }
      }
    };
    peerConnection = await _createPeerConnectionViewer(_iceServers);
    await _createOffer(peerConnection!);
    notifyListeners();
  }

  /// Close mediaStream and clear peerConnection and dataChannel
  void stopViewer() {
    if (null != localStream) {
      localStream!.getTracks().forEach((track) {
        track.stop();
        // localStream!.removeTrack(track);
      });
      localStream!.dispose();
    }

    if (null != remoteStream) {
      remoteStream!.getTracks().forEach((track) {
        track.stop();
        // remoteStream!.removeTrack(track);
      });
      remoteStream!.dispose();
    }

    if (null != dataChannel) {
      dataChannel!.close();
    }

    if (null != peerConnection) {
      // peerConnection!.removeTrack(rtpSender!);
      // peerConnection!.removeStream(localStream!);
      peerConnection!.close();
    }
  }

  /// Receive json data
  void onMessage(message) async {
    Map<String, dynamic> mapData = message;
    String action = mapData["messageType"];
    String messagePayload =
        String.fromCharCodes(base64Decode(mapData["messagePayload"]));
    switch (action) {
      case Constants.SDP_OFFER:
        String remoteClientId = mapData["senderClientId"];
        Map<String, dynamic> descriptionMap = _decoder.convert(messagePayload);
        RTCPeerConnection pc = await _createPeerConnectionMaster(
            _iceServers, offerSdpConstraints, remoteClientId);
        await pc.setRemoteDescription(RTCSessionDescription(
            descriptionMap["sdp"], descriptionMap["type"]));
        await pc.setLocalDescription(
          await pc.createAnswer(offerSdpConstraints),
        );
        RTCSessionDescription? sessionDescription =
            await pc.getLocalDescription();
        sendMessage(Constants.SDP_ANSWER,
            _encoder.convert(sessionDescription!.toMap()), remoteClientId);
        peerConnectionByClientId[remoteClientId] = pc;
        break;
      case Constants.SDP_ANSWER:
        Map<String, dynamic> descriptionMap = _decoder.convert(messagePayload);
        await peerConnection!.setRemoteDescription(RTCSessionDescription(
            descriptionMap["sdp"], descriptionMap["type"]));
        break;
      case Constants.ICE_CANDIDATE:
        Map<String, dynamic> candidateMap = _decoder.convert(messagePayload);
        RTCIceCandidate candidate = RTCIceCandidate(candidateMap["candidate"],
            candidateMap["sdpMid"], candidateMap["sdpMLineIndex"]);
        if (isMaster) {
          String remoteClientId = mapData["senderClientId"];
          if (null != peerConnectionByClientId[remoteClientId]) {
            await peerConnectionByClientId[remoteClientId]!
                .addCandidate(candidate)
                .catchError((e) {});
          }
        } else {
          if (peerConnection != null) {
            await peerConnection!.addCandidate(candidate).catchError((e) {});
          }
        }
        break;
      default:
        print("onMessage default: " + action + ", " + messagePayload);
        break;
    }
  }

  /// Create mediaStream
  Future<MediaStream> createStream(bool userScreen) async {
    MediaStream stream = userScreen
        ? await navigator.mediaDevices.getDisplayMedia(mediaConstraintsScreen)
        : await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = stream;
    return stream;
  }

  /// Change mediaStream
  Future<void> changeLocalStream() async {
    screenShare = !screenShare;
    localStream = await createStream(screenShare);
    localStream!.getTracks().forEach((track) {
      // To detect the event of stop screenShare button in browser
      if (screenShare) {
        track.onEnded = () {
          changeLocalStream();
        };
      }
      if (rtpSender != null) {
        rtpSender!.replaceTrack(track);
      }
    });
    notifyListeners();
  }

  /// Create offer
  Future<void> _createOffer(RTCPeerConnection rtcPeerConnection) async {
    await rtcPeerConnection.setLocalDescription(
      await rtcPeerConnection.createOffer(offerSdpConstraints),
    );
    RTCSessionDescription? sessionDescription =
        await rtcPeerConnection.getLocalDescription();
    sendMessage(Constants.SDP_OFFER,
        _encoder.convert(sessionDescription!.toMap()), selfId);
  }

  /// Create peerConnection as master
  Future<RTCPeerConnection> _createPeerConnectionMaster(
      Map<String, dynamic> configuration,
      Map<String, dynamic> offerSdpConstraints,
      String remoteClientId) async {
    RTCPeerConnection pc =
        await createPeerConnection(configuration, offerSdpConstraints);

    RTCDataChannelInit dataChannelInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;
    RTCDataChannel clientDataChannel =
        await pc.createDataChannel(remoteClientId, dataChannelInit);
    clientDataChannel.onDataChannelState = (dataChannelState) {
      switch (dataChannelState) {
        case RTCDataChannelState.RTCDataChannelConnecting:
          // TODO: Handle this case.
          break;
        case RTCDataChannelState.RTCDataChannelOpen:
          // TODO: Handle this case.
          break;
        case RTCDataChannelState.RTCDataChannelClosing:
          // TODO: Handle this case.
          break;
        case RTCDataChannelState.RTCDataChannelClosed:
          if (dataChannelByClientId[remoteClientId] != null) {
            dataChannelByClientId[remoteClientId]!.close();
          }
          dataChannelByClientId.remove(remoteClientId);
          break;
        default:
          break;
      }
    };
    dataChannelByClientId[remoteClientId] = clientDataChannel;

    // TODO pc.onAddTrack
    pc.onTrack = (event) async {
      if (event.track.kind == 'video') {
        RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
        await _remoteRenderer.initialize();
        _remoteRenderer.srcObject = event.streams[0];
        remoteViewList.add(RemoteViews(
            clientId: remoteClientId, videoRenderer: _remoteRenderer));
        remoteStreams.add(event.streams[0]);
        notifyListeners();
        // event.streams[0].onRemoveTrack = (track) {
        //   onRemoveStreamTrack?.call(null, track);
        // };
      }
    };
    pc.onIceCandidate = (candidate) {
      sendMessage(Constants.ICE_CANDIDATE,
          _encoder.convert(candidate.toMap()), remoteClientId);
    };
    pc.onIceConnectionState = (e) {};
    // pc.onRemoveTrack = (stream, track) {
    //   onRemoveRemoteStream?.call(null, stream);
    //   remoteStreams.removeWhere((it) {
    //     return (it.id == stream.id);
    //   });
    // };
    // pc.onRemoveStream = (stream) {
    //   onRemoveRemoteStream?.call(null, stream);
    //   remoteStreams.removeWhere((it) {
    //     return (it.id == stream.id);
    //   });
    // };
    pc.onConnectionState = (state) async {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          remoteViewList.removeWhere((view) {
            bool viewExist = false;
            if (view.clientId == remoteClientId) {
              view.videoRenderer.srcObject = null;
              viewExist = true;
            }
            return viewExist;
          });
          peerConnectionByClientId.remove(remoteClientId);
          notifyListeners();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          // TODO: Handle this case.
          break;
        default:
          break;
      }
    };
    pc.onDataChannel = (event) {
      event.onMessage = (message) {
        Map<String, dynamic> chatMessageMap = _decoder.convert(message.text);
        if (chatMessageMap["clientId"] == selfId) {
          chatMessageMap["clientId"] += "(Self)";
        }
        VideoCallChatMessage chatMessage = new VideoCallChatMessage(
            userName: chatMessageMap["clientId"],
            messageTime: DateTime.now().toString(),
            messageContent: chatMessageMap["message"]);
        messageList.insert(0, chatMessage);
        transferChatMessage(message.text);
        notifyListeners();
      };
    };

    localStream!.getTracks().forEach((track) async {
      rtpSender = await pc.addTrack(track, localStream!);
    });
    return pc;
  }

  /// Create peerConnection as viewer
  Future<RTCPeerConnection> _createPeerConnectionViewer(
      Map<String, dynamic> configuration) async {
    RTCPeerConnection pc = await createPeerConnection(_iceServers);

    RTCDataChannelInit dataChannelInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;
    dataChannel = await pc.createDataChannel(selfId, dataChannelInit);
    dataChannel!.onDataChannelState = (dataChannelState) {
      switch (dataChannelState) {
        case RTCDataChannelState.RTCDataChannelConnecting:
          // TODO: Handle this case.
          break;
        case RTCDataChannelState.RTCDataChannelOpen:
          // TODO: Handle this case.
          break;
        case RTCDataChannelState.RTCDataChannelClosing:
          // TODO: Handle this case.
          break;
        case RTCDataChannelState.RTCDataChannelClosed:
          if (dataChannel != null) {
            dataChannel!.close();
          }
          break;
        default:
          break;
      }
    };

    // TODO pc.onAddTrack
    pc.onTrack = (event) async {
      if (event.track.kind == 'video') {
        RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
        await _remoteRenderer.initialize();
        _remoteRenderer.srcObject = event.streams[0];
        remoteViewList.add(
            RemoteViews(clientId: "master", videoRenderer: _remoteRenderer));
        remoteStream = event.streams[0];
        notifyListeners();
        // remoteStream!.onRemoveTrack = (track) {
        //   onRemoveStreamTrack?.call(null, track);
        // };
      }
    };
    pc.onIceCandidate = (candidate) {
      sendMessage(Constants.ICE_CANDIDATE,
          _encoder.convert(candidate.toMap()), selfId);
    };
    pc.onIceConnectionState = (e) {};
    // pc.onRemoveTrack = (stream, track) {
    //   onRemoveRemoteStream?.call(null, stream);
    // };
    // pc.onRemoveStream = (stream) {
    //   onRemoveRemoteStream?.call(null, stream);
    //   // remoteStreams.removeWhere((it) {
    //   //   return (it.id == stream.id);
    //   // });
    // };
    pc.onConnectionState = (connectionState) async {
      switch (connectionState) {
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          remoteViewList.removeWhere((view) {
            bool viewExist = false;
            if (view.clientId == "master") {
              view.videoRenderer.srcObject = null;
              viewExist = true;
            }
            return viewExist;
          });
          notifyListeners();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          // TODO: Handle this case.
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          // TODO: Handle this case.
          break;
        default:
          break;
      }
    };
    pc.onDataChannel = (event) {
      event.onMessage = (message) {
        Map<String, dynamic> chatMessageMap = _decoder.convert(message.text);
        // onDataChannelMessage?.call(
        //     chatMessageMap["clientId"], chatMessageMap["message"]!);
        if (chatMessageMap["clientId"] == selfId) {
          chatMessageMap["clientId"] += "(Self)";
        }
        VideoCallChatMessage chatMessage = new VideoCallChatMessage(
            userName: chatMessageMap["clientId"],
            messageTime: DateTime.now().toString(),
            messageContent: chatMessageMap["message"]);
        messageList.insert(0, chatMessage);
        notifyListeners();
      };
    };

    localStream!.getTracks().forEach((track) async {
      rtpSender = await pc.addTrack(track, localStream!);
    });
    return pc;
  }

  /// Send chat message(master/viewer)
  void sendChatMessage(String text) {
    Map<String, String> chatMessageMap = Map();
    chatMessageMap["clientId"] = selfId;
    chatMessageMap["message"] = text;
    String message = _encoder.convert(chatMessageMap);
    if (isMaster) {
      for (String client in dataChannelByClientId.keys) {
        if (dataChannelByClientId[client]!.state ==
            RTCDataChannelState.RTCDataChannelOpen) {
          dataChannelByClientId[client]!.send(RTCDataChannelMessage(message));
        } else {
          print(
              "VideoCallViewModel sendChatMessage dataChannel is not open, clientId: " +
                  client);
        }
      }
    } else {
      if (dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        dataChannel!.send(RTCDataChannelMessage(message));
      } else {
        print("VideoCallViewModel sendChatMessage dataChannel is not open");
      }
    }
  }

  /// Transfer chat message(master)
  void transferChatMessage(String text) {
    for (String client in dataChannelByClientId.keys) {
      if (dataChannelByClientId[client]!.state ==
          RTCDataChannelState.RTCDataChannelOpen) {
        dataChannelByClientId[client]!.send(RTCDataChannelMessage(text));
      } else {
        print(
            "VideoCallViewModel transferChatMessage dataChannel is not open, clientId: " +
                client);
      }
    }
  }

  /// Send chat message when press enter button
  void handleSubmitted(String text) {
    textController.clear();
    sendChatMessage(text);
    if (isMaster) {
      VideoCallChatMessage chatMessage = new VideoCallChatMessage(
          userName: selfId + "(Self)",
          messageTime: DateTime.now().toString(),
          messageContent: text);
      messageList.insert(0, chatMessage);
    }
    notifyListeners();
  }

  /// Start screen share
  void startScreenShare() {
    changeLocalStream();
  }

  /// Hangup
  Future<void> hangUp() async {
    isHangUp = true;
    _webSocketManager.reconnect = !isHangUp;
    remoteViewList.forEach((view) {
      view.videoRenderer.srcObject = null;
    });
    localRenderer.srcObject = null;
    if (isMaster) {
      stopMaster();
    } else {
      stopViewer();
    }
    await close();
    notifyListeners();
  }
}

/// Define remoteView parameter
class RemoteViews {
  String clientId;
  RTCVideoRenderer videoRenderer;

  RemoteViews({required this.clientId, required this.videoRenderer});
}
