import 'package:flutter/material.dart';

import 'video_call_page.dart';

class VideoCallTmpPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      body: Container(
          margin: const EdgeInsets.only(top: 0, right: 0, bottom: 0, left: 0),
          color: Colors.lime[50],
          child: Center(
            child: new Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                new ElevatedButton(
                  child: Text("Start Master"),
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => VideoCallPage(true)));
                  },
                ),
                new ElevatedButton(
                  child: Text("Start Viewer"),
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => VideoCallPage(false)));
                  },
                ),
              ],
            ),
          )),
    );
  }
}
