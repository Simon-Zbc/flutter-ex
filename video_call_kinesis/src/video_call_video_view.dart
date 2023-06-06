import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoCallVideoView extends StatefulWidget {
  final String clientId;
  final RTCVideoRenderer videoRenderer;
  final bool isMirror;

  VideoCallVideoView(this.clientId, this.videoRenderer, this.isMirror);

  @override
  _VideoCallVideoViewState createState() => _VideoCallVideoViewState();
}

class _VideoCallVideoViewState extends State<VideoCallVideoView> {
  late String clientId;
  late RTCVideoRenderer videoRenderer;
  late bool isMirror;

  @override
  void initState() {
    clientId = widget.clientId;
    videoRenderer = widget.videoRenderer;
    isMirror = widget.isMirror;
    super.initState();
  }

  @override
  void didChangeDependencies() {
    // TODO video stream resume
    super.didChangeDependencies();
  }

  @override
  void deactivate() {
    // TODO video stream pause
    super.deactivate();
  }

  @override
  void dispose() {
    try {
      videoRenderer.dispose();
    } catch (e) {
      print("VideoCallVideoView dispose: " + e.toString());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // return RTCVideoView(videoRenderer, mirror: isMirror,);
    return Stack(children: <Widget>[
      Positioned(
        left: 0.0,
        right: 0.0,
        top: 0.0,
        bottom: 0.0,
        child: RTCVideoView(
          videoRenderer,
          mirror: isMirror,
        ),
      ),
      Positioned(
        left: 0.0,
        bottom: 0.0,
        child: Text(
          clientId,
          style:
              Theme.of(context).textTheme.subtitle1!.apply(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}
