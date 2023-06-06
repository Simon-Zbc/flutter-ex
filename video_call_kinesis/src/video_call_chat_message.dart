import 'package:flutter/material.dart';

class VideoCallChatMessage extends StatelessWidget {
  final String userName;
  final String messageContent;
  final String messageTime;

  VideoCallChatMessage(
      {required this.userName,
      required this.messageTime,
      required this.messageContent});

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return new Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          new Container(
            margin: const EdgeInsets.only(right: 16.0),
            child: new CircleAvatar(child: new Text(userName.substring(0, 1))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  new Container(
                    constraints: BoxConstraints(
                      maxWidth: screenWidth / 2,
                    ),
                    child: new Text(
                      userName,
                      style: Theme.of(context).textTheme.subtitle1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  new Container(
                    margin: const EdgeInsets.only(left: 10.0),
                    child: new Text(messageTime.substring(11, 19),
                        style: Theme.of(context).textTheme.subtitle2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              new Container(
                margin: const EdgeInsets.only(top: 5.0),
                child: Text(messageContent),
              )
            ],
          )
        ],
      ),
    );
  }
}
