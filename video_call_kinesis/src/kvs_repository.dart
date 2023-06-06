import 'dart:async';
import 'dart:convert';

import 'package:aws_kinesis_video_signaling_api/kinesis-video-signaling-2019-12-04.dart';
import 'package:aws_kinesisvideo_api/kinesisvideo-2017-09-30.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

typedef void WebSocketMessageCallback(String message);

class KvsRepository {
  static AwsClientCredentials _awsClientCredentials = new AwsClientCredentials(
      accessKey: Constants.AWS_ACCESS_KEY_ID,
      secretKey: Constants.AWS_SECRET_ACCESS_KEY);
  static KinesisVideo? _kvsClient;
  static Map<ChannelProtocol, String> _endpointChannelProtocolMap = new Map();
  static String _channelARN = "";

  static Future<String> getWssEndpoint(
      bool isMaster, String selfId, Map<String, List> iceServers) async {
    SingleMasterChannelEndpointConfiguration endpointConfiguration =
        new SingleMasterChannelEndpointConfiguration(
            protocols: [ChannelProtocol.wss, ChannelProtocol.https],
            role: isMaster ? ChannelRole.master : ChannelRole.viewer);

    _kvsClient = new KinesisVideo(
        region: Constants.AWS_REGION, credentials: _awsClientCredentials);

    // TODO create new signaling channel and get the arn of channel
    if (isMaster) {
      CreateSignalingChannelOutput signalingChannelOutput =
          await _kvsClient!.createSignalingChannel(channelName: selfId);
      _channelARN = signalingChannelOutput.channelARN;
    }

    GetSignalingChannelEndpointOutput getSignalingChannelEndpointOutput =
        await _kvsClient!.getSignalingChannelEndpoint(
            // channelARN: _channelARN,
            channelARN: Constants.AWS_CHANNEL_ARN,
            singleMasterChannelEndpointConfiguration: endpointConfiguration);

    for (ResourceEndpointListItem endpoint
        in getSignalingChannelEndpointOutput.resourceEndpointList) {
      _endpointChannelProtocolMap[endpoint.protocol] =
          endpoint.resourceEndpoint;
    }

    KinesisVideoSignalingChannels kvsSignalingChannels =
        new KinesisVideoSignalingChannels(
            region: Constants.AWS_REGION,
            credentials: _awsClientCredentials,
            endpointUrl: _endpointChannelProtocolMap[ChannelProtocol.https]);

    GetIceServerConfigResponse getIceServerConfigResponse =
        await kvsSignalingChannels.getIceServerConfig(
      // channelARN: _channelARN,
      channelARN: Constants.AWS_CHANNEL_ARN,
    );

    getIceServerConfigResponse.iceServerList.forEach((iceServer) {
      iceServers["iceServers"]!.add({
        'urls': iceServer.uris,
        'username': iceServer.username,
        'credential': iceServer.password
      });
    });

    String wssEndpoint = _endpointChannelProtocolMap[ChannelProtocol.wss]!;
    String masterEndpoint =
        wssEndpoint + "/?X-Amz-ChannelARN=" + Constants.AWS_CHANNEL_ARN;
    // _channelARN;
    String viewerEndpoint = wssEndpoint +
        "/?X-Amz-ChannelARN=" +
        // _channelARN +
        Constants.AWS_CHANNEL_ARN +
        "&X-Amz-ClientId=" +
        selfId;

    if (isMaster) {
      return masterEndpoint;
    } else {
      return viewerEndpoint;
    }
  }

  static String getSignedURL(String endpoint) {
    final DateTime dateMilli = new DateTime.now();
    final String amzDate = _getTimeStamp(dateMilli);
    final String dateStamp = _getDateStamp(dateMilli);

    Uri uri = Uri.parse(endpoint);
    const String protocol = "wss";
    const String urlProtocol = "$protocol://";
    int pathStartIndex = endpoint.indexOf("\/", urlProtocol.length);
    String host;
    String path;
    if (pathStartIndex < 0) {
      host = endpoint.substring(urlProtocol.length);
      path = "/";
    } else {
      host = endpoint.substring(urlProtocol.length, pathStartIndex);
      path = endpoint.substring(pathStartIndex);
    }

    final Map<String, String> queryParamsMap = _buildQueryParamsMap(
        uri,
        _awsClientCredentials.accessKey,
        "",
        Constants.AWS_REGION,
        amzDate,
        dateStamp);
    final String canonicalQueryString =
        _getCanonicalizedQueryString(queryParamsMap);
    final String canonicalRequest =
        _getCanonicalRequest(uri, canonicalQueryString);
    final String stringToSign = _signString(
        amzDate,
        _createCredentialScope(Constants.AWS_REGION, dateStamp),
        canonicalRequest);
    final List<int> signatureKey = _getSignatureKey(
        _awsClientCredentials.secretKey,
        dateStamp,
        Constants.AWS_REGION,
        Constants.KINESIS_VIDEO_SERVICE);
    final String signature =
        _hexEncode(_hmacSha256(stringToSign, signatureKey));
    final String signedCanonicalQueryString = canonicalQueryString +
        "&" +
        Constants.X_AMZ_SIGNATURE +
        "=" +
        signature;

    return protocol + '://' + host + '/?' + signedCanonicalQueryString;
  }

  static deleteSignalingChannel() async {
    await _kvsClient!.deleteSignalingChannel(channelARN: _channelARN);
  }

  static String _getTimeStamp(DateTime dateMilli) {
    return dateMilli
        .toUtc()
        .toString()
        .replaceAll(RegExp(r'\.\d*Z$'), 'Z')
        .replaceAll(RegExp(r'[:-]|\.\d{3}'), '')
        .split(' ')
        .join('T');
  }

  static String _getDateStamp(DateTime dateMilli) {
    return dateMilli.toString().substring(0, 10).replaceAll('-', '');
  }

  static Map<String, String> _buildQueryParamsMap(Uri uri, String accessKey,
      String sessionToken, String region, String amzDate, String datestamp) {
    Map<String, String> queryParams = new Map();
    queryParams[Constants.X_AMZ_ALGORITHM] =
        Constants.ALGORITHM_AWS4_HMAC_SHA_256;
    queryParams[Constants.X_AMZ_CREDENTIAL] =
        accessKey + "/" + _createCredentialScope(region, datestamp);
    queryParams[Constants.X_AMZ_DATE] = amzDate;
    queryParams[Constants.X_AMZ_EXPIRES] = "299";
    queryParams[Constants.X_AMZ_SIGNED_HEADERS] =
        Constants.SIGNED_HEADERS;

    if (sessionToken.isNotEmpty) {
      queryParams[Constants.X_AMZ_SECURITY_TOKEN] =
          Uri.encodeComponent(sessionToken);
    }

    queryParams.addAll(uri.queryParameters);
    return queryParams;
  }

  static String _createCredentialScope(String region, String datestamp) {
    return datestamp +
        "/" +
        region +
        "/" +
        Constants.KINESIS_VIDEO_SERVICE +
        "/" +
        Constants.AWS4_REQUEST_TYPE;
  }

  static String _getCanonicalizedQueryString(
      Map<String, String> queryParamsMap) {
    final sortedQuery = [];
    queryParamsMap.forEach((key, value) {
      sortedQuery.add(key.toString());
    });
    sortedQuery.sort();

    final canonicalQueryStrings = [];
    sortedQuery.forEach((key) {
      canonicalQueryStrings
          .add('$key=${Uri.encodeComponent(queryParamsMap[key].toString())}');
    });

    return canonicalQueryStrings.join('&');
  }

  static String _getCanonicalRequest(Uri uri, String canonicalQuerystring) {
    final String payloadHash = _hashPayload("");
    final String canonicalUri = _getCanonicalUri(uri);
    final String canonicalHeaders =
        "host:" + uri.host + Constants.NEW_LINE_DELIMITER;
    final String canonicalRequest = Constants.KINESIS_VIDEO_METHOD +
        Constants.NEW_LINE_DELIMITER +
        canonicalUri +
        Constants.NEW_LINE_DELIMITER +
        canonicalQuerystring +
        Constants.NEW_LINE_DELIMITER +
        canonicalHeaders +
        Constants.NEW_LINE_DELIMITER +
        Constants.SIGNED_HEADERS +
        Constants.NEW_LINE_DELIMITER +
        payloadHash;

    return canonicalRequest;
  }

  static String _getCanonicalUri(Uri uri) {
    String uriPath = uri.path;
    return uriPath.isEmpty ? "/" : uriPath;
  }

  static String _hashPayload(String payload) {
    return _hexEncode(_hash(utf8.encode(payload)));
  }

  static List<int> _hash(List<int> value) {
    return sha256.convert(value).bytes;
  }

  static String _hexEncode(List<int> value) {
    return hex.encode(value);
  }

  static String _signString(
      String amzDate, String credentialScope, String canonicalRequest) {
    final String stringToSign = Constants.ALGORITHM_AWS4_HMAC_SHA_256 +
        Constants.NEW_LINE_DELIMITER +
        amzDate +
        Constants.NEW_LINE_DELIMITER +
        credentialScope +
        Constants.NEW_LINE_DELIMITER +
        _hashPayload(canonicalRequest);
    return stringToSign;
  }

  static List<int> _getSignatureKey(final String key, final String dateStamp,
      final String regionName, final String serviceName) {
    final List<int> kSecret = utf8.encode("AWS4" + key);
    final List<int> kDate = _hmacSha256(dateStamp, kSecret);
    final List<int> kRegion = _hmacSha256(regionName, kDate);
    final List<int> kService = _hmacSha256(serviceName, kRegion);
    return _hmacSha256(Constants.AWS4_REQUEST_TYPE, kService);
  }

  static List<int> _hmacSha256(final String data, final List<int> key) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(data));
    return digest.bytes;
  }
}
