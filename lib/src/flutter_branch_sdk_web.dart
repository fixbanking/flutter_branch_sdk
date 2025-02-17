import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'app_tracking_transparency.dart';
import 'flutter_branch_sdk_platform_interface.dart';
import 'web/branch_js.dart';

/// A workaround to deep-converting an object from JS to a Dart Object.
dynamic _jsObjectToDartObject(data) => json.decode(jsonStringify(data));
dynamic _dartObjectToJsObject(data) => jsonParse(json.encode(data));
Map<String, String> _metaData = {};

/// A web implementation of the FlutterBranchSdk plugin.
class FlutterBranchSdk extends FlutterBranchSdkPlatform {
  static FlutterBranchSdk _singleton;

  /// Constructs a singleton instance of [MethodChannelFlutterBranchSdk].
  factory FlutterBranchSdk() {
    if (_singleton == null) {
      _singleton = FlutterBranchSdk._();
    }
    return _singleton;
  }

  FlutterBranchSdk._();

  /// Registers this class as the default instance of [SharePlatform].
  static void registerWith(Registrar registrar) {
    FlutterBranchSdkPlatform.instance = FlutterBranchSdk();
  }

  static final StreamController<Map<String, dynamic>> _initSessionStream =
      StreamController<Map<String, dynamic>>();
  static bool _userIdentified = false;

  @Deprecated('version 5.0.0')
  @override
  void initWeb({String branchKey}) {}

  ///Initialises a session with the Branch API
  ///Listen click em Branch Deeplinks
  @override
  Stream<Map<dynamic, dynamic>> initSession() {
    getLatestReferringParams().then((data) {
      if (data.isNotEmpty) {
        _initSessionStream.sink
            .add(data.map((key, value) => MapEntry('$key', value)));
      } else {
        _initSessionStream.sink.add({});
      }
    });

    return _initSessionStream.stream;
  }

  ///Returns the last parameters associated with the link that referred the user, not really applicaple for web though
  @override
  Future<Map<dynamic, dynamic>> getLatestReferringParams() {
    final Completer<Map<dynamic, dynamic>> response = Completer();

    try {
      BranchJS.data(allowInterop((err, data) {
        if (err == null) {
          if (data != null) {
            var responseData =
                Map<dynamic, dynamic>.from(_jsObjectToDartObject(data));
            response.complete(responseData['data_parsed'] ?? {});
          } else {
            response.complete({});
          }
        } else {
          response.completeError(err);
        }
      }));
    } catch (e) {
      print('getLatestReferringParams() error: $e');
      response.completeError(e);
    }
    return response.future;
  }

  ///Returns the first parameters associated with the link that referred the user
  @override
  Future<Map<dynamic, dynamic>> getFirstReferringParams() {
    final Completer<Map<dynamic, dynamic>> response =
        Completer<Map<dynamic, dynamic>>();

    try {
      BranchJS.first(allowInterop((err, data) {
        if (err == null) {
          if (data != null) {
            var responseData =
                Map<dynamic, dynamic>.from(_jsObjectToDartObject(data));
            response.complete(responseData['data_parsed'] ?? {});
          } else {
            response.complete({});
          }
        } else {
          response.completeError(err);
        }
      }));
    } catch (e) {
      print('getFirstReferringParams() error: $e');
      response.completeError(e);
    }
    return response.future;
  }

  ///Identifies the current user to the Branch API by supplying a unique identifier as a userId value
  @override
  void setIdentity(String userId) {
    try {
      BranchJS.setIdentity(userId, allowInterop((error, data) {
        if (error == null) {
          _userIdentified = true;
        }
      }));
    } catch (e) {
      print('setIdentity() error: $e');
    }
  }

  ///This method should be called if you know that a different person is about to use the app
  @override
  void logout() {
    try {
      BranchJS.logout(allowInterop((error) {
        if (error == null) {
          _userIdentified = false;
        }
      }));
    } catch (e) {
      print('logout() error: $e');
    }
  }

  ///Method to change the Tracking state. If disabled SDK will not track any user data or state.
  ///SDK will not send any network calls except for deep linking when tracking is disabled
  @override
  void disableTracking(bool value) {
    try {
      BranchJS.disableTracking(value);
    } catch (e) {
      print('disableTracking() error: $e');
    }
  }

  ///Creates a short url for the BUO
  @override
  Future<BranchResponse> getShortUrl(
      {BranchUniversalObject buo, BranchLinkProperties linkProperties}) async {
    Map<String, dynamic> data = buo.toMapWeb();
    linkProperties.getControlParams().forEach((key, value) {
      data['$key'] = value;
    });

    Map<String, dynamic> linkData = {
      ...linkProperties.toMapWeb(),
      'data': data
    };

    Completer<BranchResponse> responseCompleter = Completer();

    try {
      BranchJS.link(_dartObjectToJsObject(linkData), allowInterop((err, url) {
        if (err == null) {
          responseCompleter.complete(BranchResponse.success(result: url));
        } else {
          responseCompleter.completeError(
              BranchResponse.error(errorCode: '-1', errorMessage: err));
        }
      }));
    } catch (e) {
      print('getShortUrl() error: $e');
      responseCompleter.completeError(BranchResponse.error(
          errorCode: '-1', errorMessage: 'getShortUrl() error'));
    }
    return responseCompleter.future;
  }

  ///Showing a Share Sheet - Implemented via navigator share if available, otherwise browser prompt.
  @override
  Future<BranchResponse> showShareSheet(
      {BranchUniversalObject buo,
      BranchLinkProperties linkProperties,
      String messageText,
      String androidMessageTitle = '',
      String androidSharingTitle = ''}) async {
    BranchResponse response =
        await getShortUrl(buo: buo, linkProperties: linkProperties);
    if (response.success) {
      try {
        await promiseToFuture(navigatorShare(_dartObjectToJsObject({
          "title": messageText,
          "text": buo.title,
          "url": response.result
        })));
      } catch (e) {
        browserPrompt(messageText, response.result);
      }
    }
    return response;
  }

  ///Logs this BranchEvent to Branch for tracking and analytics
  @override
  void trackContent(
      {List<BranchUniversalObject> buo, BranchEvent branchEvent}) {
    JsArray<Object> contentItems = JsArray();

    buo.forEach((element) {
      contentItems.add(_dartObjectToJsObject(element.toMapWeb()));
    });

    try {
      BranchJS.logEvent(branchEvent.eventName,
          _dartObjectToJsObject(branchEvent.toMapWeb()), contentItems);
    } catch (e) {
      print('trackContent() error: $e');
    }
  }

  ///Logs this BranchEvent to Branch for tracking and analytics
  @override
  void trackContentWithoutBuo({BranchEvent branchEvent}) {
    try {
      BranchJS.logEvent(
          branchEvent.eventName, _dartObjectToJsObject(branchEvent.toMapWeb()));
    } catch (e) {
      print('trackContentWithoutBuo() error: $e');
    }
  }

  ///Mark the content referred by this object as viewed. This increment the view count of the contents referred by this object.
  @override
  void registerView({BranchUniversalObject buo}) {
    BranchEvent branchEvent =
        BranchEvent.standardEvent(BranchStandardEvent.VIEW_ITEM);

    // This might not be exactly the same thing as BUO.registerView, but there's no clear implementation for web sdk
    trackContent(buo: [buo], branchEvent: branchEvent);
  }

  ///Add key value pairs to all requests
  @override
  void setRequestMetadata(String key, String value) {
    _metaData[key] = value;
  }

  ///For Android: Publish this BUO with Google app indexing so that the contents will be available with google search
  ///For iOS:     List items on Spotlight
  @override
  Future<bool> listOnSearch(
      {BranchUniversalObject buo, BranchLinkProperties linkProperties}) async {
    throw UnsupportedError('listOnSearch() Not supported by Branch JS SDK');
  }

  ///For Android: Remove the BUO from the local indexing if it is added to the local indexing already
  ///             This will remove the content from Google(Firebase) and other supported Indexing services
  ///For iOS:     Remove Branch Universal Object from Spotlight if privately indexed
  @override
  Future<bool> removeFromSearch(
      {BranchUniversalObject buo, BranchLinkProperties linkProperties}) async {
    throw UnsupportedError('removeFromSearch() Not supported by Branch JS SDK');
  }

  ///Retrieves rewards for the current user/session
  @Deprecated('version 4.0.0')
  @override
  Future<BranchResponse> loadRewards({String bucket = 'default'}) async {
    Completer<BranchResponse> responseCompleter = Completer();

    try {
      BranchJS.credits(allowInterop((err, data) {
        if (err == null) {
          var parsedData = Map<String, int>.from(_jsObjectToDartObject(data));
          if (parsedData.isNotEmpty) {
            responseCompleter.complete(BranchResponse.success(
                result: parsedData.containsKey(bucket)
                    ? parsedData[bucket]
                    : parsedData['default']));
          } else {
            responseCompleter.complete(BranchResponse.success(result: 0));
          }
        } else {
          responseCompleter.complete(
              BranchResponse.error(errorCode: '999', errorMessage: err));
        }
      }));
    } catch (e) {
      print('loadRewards() error: $e');
      responseCompleter.complete(BranchResponse.error(
          errorCode: '-1', errorMessage: 'loadRewards() error'));
    }
    return responseCompleter.future;
  }

  ///Redeems the specified number of credits. if there are sufficient credits within it.
  ///If the number to redeem exceeds the number available in the bucket, all of the
  ///available credits will be redeemed instead.
  @Deprecated('version 4.0.0')
  @override
  Future<BranchResponse> redeemRewards(
      {int count, String bucket = 'default'}) async {
    Completer<BranchResponse> responseCompleter = Completer();

    try {
      BranchJS.redeem(count, bucket, allowInterop((err) {
        if (err == null) {
          responseCompleter.complete(BranchResponse.success(result: true));
        } else {
          responseCompleter.complete(BranchResponse.error(
              errorCode: '999', errorMessage: err.toString()));
        }
      }));
    } catch (e) {
      print('redeemRewards() error: $e');
      responseCompleter.complete(BranchResponse.error(
          errorCode: '-1', errorMessage: 'redeemRewards() error'));
    }
    return responseCompleter.future;
  }

  ///Gets the credit history
  @Deprecated('version 4.0.0')
  @override
  Future<BranchResponse> getCreditHistory({String bucket = 'default'}) async {
    Completer<BranchResponse> responseCompleter = Completer();

    try {
      BranchJS.creditHistory(_dartObjectToJsObject({'bucket': bucket}),
          allowInterop((err, data) {
        if (err == null) {
          if (data != null) {
            responseCompleter.complete(
                BranchResponse.success(result: _jsObjectToDartObject(data)));
          } else {
            responseCompleter.complete(BranchResponse.success(result: {}));
          }
        } else {
          responseCompleter.complete(BranchResponse.error(
              errorCode: '999', errorMessage: err.toString()));
        }
      }));
    } catch (e) {
      print('getCreditHistory() error: $e');
      responseCompleter.complete(BranchResponse.error(
          errorCode: '-1', errorMessage: 'getCreditHistory() error'));
    }

    return responseCompleter.future;
  }

  ///Set time window for SKAdNetwork callouts in Hours (Only iOS)
  ///By default, Branch limits calls to SKAdNetwork to within 72 hours after first install.
  @override
  void setIOSSKAdNetworkMaxTime(int hours) {
    throw UnsupportedError(
        'setIOSSKAdNetworkMaxTime() Not available in Branch JS SDK');
  }

  ///Indicates whether or not this user has a custom identity specified for them. Note that this is independent of installs.
  ///If you call setIdentity, this device will have that identity associated with this user until logout is called.
  ///This includes persisting through uninstalls, as we track device id.
  // NOTE: This is not really accurate for persistent checks...
  @override
  Future<bool> isUserIdentified() async {
    return Future.value(_userIdentified);
  }

  /// request AppTracking Autorization and return AppTrackingStatus
  /// on Android returns notSupported
  @override
  Future<AppTrackingStatus> requestTrackingAuthorization() async {
    throw UnsupportedError(
        'requestTrackingAuthorization() Not available in Branch JS SDK');
  }

  /// return AppTrackingStatus
  /// on Android returns notSupported
  @override
  Future<AppTrackingStatus> getTrackingAuthorizationStatus() async {
    throw UnsupportedError(
        'getTrackingAuthorizationStatus() Not available in Branch JS SDK');
  }

  /// return advertising identifier (ie tracking data).
  /// on Android returns empty string
  @override
  Future<String> getAdvertisingIdentifier() async {
    throw UnsupportedError(
        'getAdvertisingIdentifier() Not available in Branch JS SDK');
  }

  ///Use the SDK integration validator to check that you've added the Branch SDK and
  ///handle deep links correctly when you first integrate Branch into your app.
  @override
  void validateSDKIntegration() {
    throw UnsupportedError(
        'validateSDKIntegration() not available in Branch JS SDK');
  }

  ///Sets the duration in milliseconds that the system should wait for initializing
  ///a network * request.
  @override
  void setConnectTimeout(int connectTimeout) {
    throw UnsupportedError(
        'setConnectTimeout() Not available in Branch JS SDK');
  }

  ///Sets the duration in milliseconds that the system should wait for a response
  ///before timing out any Branch API.
  ///Default 5500 ms. Note that this is the total time allocated for all request
  ///retries as set in setRetryCount(int).
  @override
  void setTimeout(int timeout) {
    throw UnsupportedError('setTimeout() Not available in Branch JS SDK');
  }

  ///Sets the max number of times to re-attempt a timed-out request to the Branch API, before
  /// considering the request to have failed entirely. Default to 3.
  /// Note that the the network timeout, as set in setNetworkTimeout(int),
  /// together with the retry interval value from setRetryInterval(int) will
  /// determine if the max retry count will be attempted.
  @override
  void setRetryCount(int retryCount) {
    throw UnsupportedError('setRetryCount() Not available in Branch JS SDK');
  }

  ///Sets the amount of time in milliseconds to wait before re-attempting a
  ///timed-out request to the Branch API. Default 1000 ms.
  @override
  void setRetryInterval(int retryInterval) {
    throw UnsupportedError('setRetryInterval() Not available in Branch JS SDK');
  }

  void close() {
    _initSessionStream.close();
  }
}
