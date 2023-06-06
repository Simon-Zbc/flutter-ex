import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'video_call_view_model.dart';
import 'video_call_video_view.dart';
import 'custom_floating_action_button_location.dart';

class VideoCallPage extends StatelessWidget {
  final bool isMaster;

  VideoCallPage(this.isMaster);

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double screenBottom = MediaQuery.of(context).viewInsets.bottom;

    return ChangeNotifierProvider<VideoCallViewModel>(
      create: (context) => VideoCallViewModel(isMaster),
      builder: (context, child) {
        return Scaffold(
          // resizeToAvoidBottomInset: false,
          floatingActionButtonLocation: CustomFloatingActionButtonLocation(
              FloatingActionButtonLocation.centerFloat,
              0,
              screenBottom == 0 ? 0 : -50),
          floatingActionButton: SizedBox(
              width: 360.0,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Consumer<VideoCallViewModel>(
                      builder: (context, viewModel, _) {
                        return FloatingActionButton(
                          child: Icon(viewModel.screenShare
                              ? Icons.stop_screen_share
                              : Icons.screen_share),
                          tooltip: 'Screen Share',
                          onPressed: viewModel.startScreenShare,
                          backgroundColor:
                              !viewModel.screenShare ? Colors.blue : Colors.red,
                          heroTag: 'ScreenShare',
                          mini: true,
                        );
                      },
                    ),
                    Consumer<VideoCallViewModel>(
                      builder: (context, viewModel, _) {
                        return FloatingActionButton(
                          child:
                              Icon(viewModel.micOn ? Icons.mic : Icons.mic_off),
                          onPressed: viewModel.muteMic,
                          heroTag: 'Mute',
                          mini: true,
                        );
                      },
                    ),
                    Consumer<VideoCallViewModel>(
                      builder: (context, viewModel, _) {
                        return FloatingActionButton(
                          child: Icon(viewModel.cameraOn
                              ? Icons.camera_alt
                              : Icons.camera_alt_outlined),
                          tooltip: 'Camera',
                          onPressed: viewModel.turnCamera,
                          heroTag: 'Camera',
                          mini: true,
                        );
                      },
                    ),
                    Consumer<VideoCallViewModel>(
                      builder: (context, viewModel, _) {
                        return FloatingActionButton(
                          child: Icon(viewModel.chatOn
                              ? Icons.message
                              : Icons.message_outlined),
                          tooltip: 'Chat Message',
                          onPressed: () {
                            viewModel.turnMessage();
                          },
                          heroTag: 'Chat',
                          mini: true,
                        );
                      },
                    ),
                    Consumer<VideoCallViewModel>(
                      builder: (context, viewModel, _) {
                        return FloatingActionButton(
                          child: const Icon(Icons.switch_camera),
                          tooltip: 'Add localView to remoteView for test',
                          onPressed: viewModel.switchCamera,
                          heroTag: 'SwitchCamera',
                          mini: true,
                        );
                      },
                    ),
                    Consumer<VideoCallViewModel>(
                      builder: (context, viewModel, _) {
                        return FloatingActionButton(
                          onPressed: () {
                            viewModel.hangUp();
                            Navigator.pop(context);
                          },
                          tooltip: 'HangUp',
                          child: const Icon(Icons.call_end),
                          backgroundColor: Colors.red,
                          heroTag: 'HangUp',
                          mini: true,
                        );
                      },
                    ),
                  ])),
          body: OrientationBuilder(builder: (context, orientation) {
            return Column(
              children: <Widget>[
                Consumer<VideoCallViewModel>(builder: (context, viewModel, _) {
                  return Container(
                    decoration: BoxDecoration(color: Colors.black),
                    width: screenWidth,
                    height: viewModel.chatOn ? screenHeight / 2 : screenHeight,
                    child: Stack(children: <Widget>[
                      Positioned(
                        left: 0.0,
                        right: 0.0,
                        top: 0.0,
                        bottom: 0.0,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                          width: screenWidth,
                          height: viewModel.chatOn
                              ? screenHeight / 2
                              : screenHeight,
                          child: GridView.builder(
                            shrinkWrap: true,
                            itemCount: viewModel.remoteViewList.length,
                            padding: EdgeInsets.all(0),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:
                                  viewModel.remoteViewList.length == 0
                                      ? 1
                                      : viewModel.remoteViewList.length > 5
                                          ? 5
                                          : viewModel.remoteViewList.length,
                              crossAxisSpacing: 0,
                              mainAxisSpacing: 0,
                              childAspectRatio: 4 / 3,
                            ),
                            itemBuilder: (context, index) {
                              return viewModel.remoteViewList.length == 0
                                  ? null
                                  : _buildGridItem(
                                      context,
                                      viewModel,
                                      viewModel.remoteViewList[index],
                                      screenWidth,
                                      screenHeight);
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0.0,
                        bottom: 0.0,
                        child: Container(
                          width: orientation == Orientation.portrait
                              ? 120.0
                              : 160.0,
                          height: orientation == Orientation.portrait
                              ? 160.0
                              : 120.0,
                          child: VideoCallVideoView(
                              viewModel.selfId, viewModel.localRenderer, true),
                        ),
                      ),
                    ]),
                  );
                }),
                Consumer<VideoCallViewModel>(builder: (context, viewModel, _) {
                  return Offstage(
                    offstage: !viewModel.chatOn,
                    child: Container(
                      width: screenWidth,
                      height: screenBottom == 0
                          ? (screenHeight / 2 - 80)
                          : (screenHeight / 2 - screenBottom),
                      child: Column(
                        children: <Widget>[
                          Flexible(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8.0),
                              reverse: true,
                              itemCount: viewModel.messageList.length,
                              itemBuilder: (context, i) =>
                                  viewModel.messageList[i],
                            ),
                          ),
                          Divider(height: 1.0),
                          Container(
                            decoration: BoxDecoration(
                                color: Theme.of(context).cardColor),
                            margin: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Row(
                              children: <Widget>[
                                Flexible(
                                  child: TextField(
                                    controller: viewModel.textController,
                                    onSubmitted: viewModel.handleSubmitted,
                                    decoration: InputDecoration.collapsed(
                                        hintText: "Send a message"),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4.0),
                                  child: IconButton(
                                      padding: EdgeInsets.all(0.0),
                                      onPressed: () =>
                                          viewModel.handleSubmitted(
                                              viewModel.textController.text),
                                      icon: Icon(
                                        Icons.send,
                                        color: Colors.blue,
                                      )),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        );
      },
    );
  }

  _buildGridItem(context, viewModel, remoteView, layoutWidth, layoutHeight) {
    return Container(
      width: layoutWidth,
      height: viewModel.chatOn ? layoutHeight / 2 : layoutHeight,
      child: VideoCallVideoView(
        remoteView.clientId,
        remoteView.videoRenderer,
        viewModel.screenShare,
      ),
    );
  }
}
