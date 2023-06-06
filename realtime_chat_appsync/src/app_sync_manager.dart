import 'dart:convert';

import 'package:amazon_cognito_identity_dart_2/sig_v4.dart';

class AppSyncManager {
  final AuthorizationType authorizationType;

  final String host;

  final String? region;

  final String? awsAccessKey;

  final String? awsSecretAccessKey;

  final String? apiKey;

  AppSyncManager({
    required this.authorizationType,
    required this.host,
    this.region,
    this.awsAccessKey,
    this.awsSecretAccessKey,
    this.apiKey,
  }) {
    assert(authorizationType == AuthorizationType.cognito ||
        (authorizationType == AuthorizationType.iam &&
            awsAccessKey != null &&
            awsSecretAccessKey != null &&
            region != null) ||
        (authorizationType == AuthorizationType.apiKey && apiKey != null));
  }

  getAppSyncRequestUrl({String? token}) {
    // AppSync header
    Map<String, String> apiHeader = {};
    switch (authorizationType) {
      case AuthorizationType.cognito:
        apiHeader = getAuthHeaderByCognito(token);
        break;
      case AuthorizationType.iam:
        apiHeader = getAuthHeaderByIAM(connectEndpoint, {});
        break;
      case AuthorizationType.apiKey:
        apiHeader = getAuthHeaderByApiKey();
        break;
      default:
        apiHeader = getAuthHeaderByCognito(token);
        break;
    }

    List<int> headerBytes = utf8.encode(jsonEncode(apiHeader));
    List<int> payloadBytes = utf8.encode(jsonEncode({}));
    String requestUrl = wssEndpoint +
        '?header=' +
        base64.encode(headerBytes) +
        '&payload=' +
        base64.encode(payloadBytes);
    return requestUrl;
  }

  Map<String, String> getAuthHeaderByCognito(String? token) {
    Map<String, String> apiHeader = {
      'host': graphqlEndpoint,
      'Authorization': token ?? '',
    };
    return apiHeader;
  }

  Map<String, String> getAuthHeaderByIAM(String endpoint, Map body) {
    if ((awsAccessKey?.isEmpty ?? true) || (awsSecretAccessKey?.isEmpty ?? true)) {
      return {};
    }
    final DateTime dateMilli = DateTime.now();
    String amzDate = getTimeStamp(dateMilli);

    AwsSigV4Client sigV4Client = AwsSigV4Client(
      awsAccessKey ?? "",
      awsSecretAccessKey ?? "",
      endpoint,
      serviceName: "appsync",
      region: region ?? "",
      defaultContentType: "application/json; charset=UTF-8",
      defaultAcceptType: "application/json, text/javascript",
    );

    Map<String, String> headers = {
      'content-encoding': 'amz-1.0',
    };

    SigV4Request sigV4Request = SigV4Request(
      sigV4Client,
      path: "",
      method: "POST",
      headers: headers,
      body: body,
    );

    String? authorization = sigV4Request.headers!["Authorization"];
    // AppSync header
    Map<String, String> apiHeader = {
      'accept': 'application/json, text/javascript',
      'content-encoding': 'amz-1.0',
      'content-type': 'application/json; charset=UTF-8',
      'host': "",
      'x-amz-date': amzDate,
      'Authorization': authorization ?? "",
    };
    return apiHeader;
  }

  Map<String, String> getAuthHeaderByApiKey() {
    Map<String, String> apiHeader = {
      'host': graphqlEndpoint,
      'x-api-key': apiKey ?? '',
    };
    return apiHeader;
  }

  String get graphqlEndpoint {
    return host.replaceAll("https://", "").replaceAll("/graphql", "");
  }

  String get connectEndpoint {
    return host + "/connect";
  }

  String get wssEndpoint {
    return host.replaceAll("https", "wss").replaceAll("appsync-api", "appsync-realtime-api");
  }

  String getTimeStamp(DateTime time) {
    return time
        .toUtc()
        .toString()
        .replaceAll(RegExp(r'\.\d*Z$'), 'Z')
        .replaceAll(RegExp(r'[:-]|\.\d{3}'), '')
        .split(' ')
        .join('T');
  }
}