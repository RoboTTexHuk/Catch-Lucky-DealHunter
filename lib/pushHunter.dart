// -----------------------------------------------------------------------------
// Roulette-flavored refactor with lightning loader
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
// Если нет – удали строку ниже или поправь под свои реальные классы.
import 'main.dart' show MafiaHarbor, CaptainHarbor;

// ============================================================================
// Рулеточная инфраструктура и паттерны
// ============================================================================

class WheelLogger {
  const WheelLogger();
  void wheelLog(Object wheelMsg) =>
      debugPrint('[WheelLogger] $wheelMsg');
  void wheelWarn(Object wheelMsg) =>
      debugPrint('[WheelLogger/WARN] $wheelMsg');
  void wheelErr(Object wheelMsg) =>
      debugPrint('[WheelLogger/ERR] $wheelMsg');
}

class WheelVault {
  static final WheelVault _wheelSingle = WheelVault._();
  WheelVault._();
  factory WheelVault() => _wheelSingle;

  final WheelLogger wheelWheel = const WheelLogger();
}

// ============================================================================
// Константы (статистика/кеш)
// ============================================================================

const String kWheelLoadedOnceKey = 'wheel_loaded_once';
const String kWheelStatEndpoint =
    'https://getgame.portalroullete.bar/stat';
const String kWheelCachedFcmKey = 'wheel_cached_fcm';

// ============================================================================
// Рулеточные утилиты: WheelKit
// ============================================================================

class WheelKit {
  // Похоже ли на "голый" e-mail без схемы
  static bool wheelLooksLikeBareMail(Uri wheelU) {
    final wheelS = wheelU.scheme;
    if (wheelS.isNotEmpty) return false;
    final wheelRaw = wheelU.toString();
    return wheelRaw.contains('@') && !wheelRaw.contains(' ');
  }

  // Превращает "bare" или обычный URL в mailto:
  static Uri wheelToMailto(Uri wheelU) {
    final wheelFull = wheelU.toString();
    final wheelBits = wheelFull.split('?');
    final wheelWho = wheelBits.first;
    final wheelQp = wheelBits.length > 1
        ? Uri.splitQueryString(wheelBits[1])
        : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: wheelWho,
      queryParameters: wheelQp.isEmpty ? null : wheelQp,
    );
  }

  // Делает Gmail compose-ссылку
  static Uri wheelGmailize(Uri wheelM) {
    final wheelQp = wheelM.queryParameters;
    final wheelParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (wheelM.path.isNotEmpty) 'to': wheelM.path,
      if ((wheelQp['subject'] ?? '').isNotEmpty)
        'su': wheelQp['subject']!,
      if ((wheelQp['body'] ?? '').isNotEmpty)
        'body': wheelQp['body']!,
      if ((wheelQp['cc'] ?? '').isNotEmpty)
        'cc': wheelQp['cc']!,
      if ((wheelQp['bcc'] ?? '').isNotEmpty)
        'bcc': wheelQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', wheelParams);
  }

  static String wheelJustDigits(String wheelS) =>
      wheelS.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия внешних ссылок/протоколов (WheelLinker)
// ============================================================================

class WheelLinker {
  static Future<bool> wheelOpen(Uri wheelU) async {
    try {
      if (await launchUrl(
        wheelU,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        wheelU,
        mode: LaunchMode.externalApplication,
      );
    } catch (wheelE) {
      debugPrint('WheelLinker error: $wheelE; url=$wheelU');
      try {
        return await launchUrl(
          wheelU,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler — рулеточный крупье в бэкграунде
// ============================================================================

@pragma('vm:entry-point')
Future<void> wheelBgDealer(RemoteMessage wheelSpinMsg) async {
  debugPrint("Spin ID: ${wheelSpinMsg.messageId}");
  debugPrint("Spin Data: ${wheelSpinMsg.data}");
}

// ============================================================================
// Рулеточный Device Deck: информация об устройстве
// ============================================================================

class WheelDeviceDeck {
  String? wheelDeviceId;
  String? wheelSessionId = 'wheel-one-off';
  String? wheelPlatformKind; // android/ios
  String? wheelOsBuild;
  String? wheelAppVersion;
  String? wheelLocale;
  String? wheelTimezone;
  bool wheelPushEnabled = true;

  Future<void> wheelInit() async {
    final wheelInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final wheelA = await wheelInfo.androidInfo;
      wheelDeviceId = wheelA.id;
      wheelPlatformKind = 'android';
      wheelOsBuild = wheelA.version.release;
    } else if (Platform.isIOS) {
      final wheelI = await wheelInfo.iosInfo;
      wheelDeviceId = wheelI.identifierForVendor;
      wheelPlatformKind = 'ios';
      wheelOsBuild = wheelI.systemVersion;
    }

    final wheelPkg = await PackageInfo.fromPlatform();
    wheelAppVersion = wheelPkg.version;
    wheelLocale = Platform.localeName.split('_').first;
    wheelTimezone = timezone.local.name;
    wheelSessionId =
    'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> wheelAsMap({String? wheelFcm}) => {
    'fcm_token': wheelFcm ?? 'missing_token',
    'device_id': wheelDeviceId ?? 'missing_id',
    'app_name': 'retroneonquiz',
    'instance_id': wheelSessionId ?? 'missing_session',
    'platform': wheelPlatformKind ?? 'missing_system',
    'os_version': wheelOsBuild ?? 'missing_build',
    'app_version': wheelAppVersion ?? 'missing_app',
    'language': wheelLocale ?? 'en',
    'timezone': wheelTimezone ?? 'UTC',
    'push_enabled': wheelPushEnabled,
  };
}

// ============================================================================
// Рулеточный шпион: AppsFlyer (WheelSpy)
// ============================================================================

class WheelSpy {
  AppsFlyerOptions? wheelOptions;
  AppsflyerSdk? wheelSdk;

  String wheelAfUid = '';
  String wheelAfData = '';

  void wheelStart({VoidCallback? onWheelUpdate}) {
    final opts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6755681349',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    wheelOptions = opts;
    wheelSdk = AppsflyerSdk(opts);

    wheelSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    wheelSdk?.startSDK(
      onSuccess: () =>
          WheelVault().wheelWheel.wheelLog('WheelSpy started'),
      onError: (code, msg) =>
          WheelVault().wheelWheel.wheelErr(
              'WheelSpy error $code: $msg'),
    );

    wheelSdk?.onInstallConversionData((value) {
      wheelAfData = value.toString();
      onWheelUpdate?.call();
    });

    wheelSdk?.getAppsFlyerUID().then((value) {
      wheelAfUid = value.toString();
      onWheelUpdate?.call();
    });
  }
}

// ============================================================================
// Рулеточный мост для FCM токена (WheelFcmBridge)
// ============================================================================

class WheelFcmBridge {
  final WheelLogger _wheelLog = const WheelLogger();
  String? _wheelToken;
  final List<void Function(String)> _wheelWaiters =
  <void Function(String)>[];

  String? get wheelToken => _wheelToken;

  WheelFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall wheelCall) async {
      if (wheelCall.method == 'setToken') {
        final String wheelTokenString =
        wheelCall.arguments as String;
        if (wheelTokenString.isNotEmpty) {
          _wheelSetToken(wheelTokenString);
        }
      }
    });

    _wheelRestoreToken();
  }

  Future<void> _wheelRestoreToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached =
      prefs.getString(kWheelCachedFcmKey);
      if (cached != null && cached.isNotEmpty) {
        _wheelSetToken(cached, notify: false);
      }
    } catch (_) {}
  }

  Future<void> _wheelPersistToken(String t) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kWheelCachedFcmKey, t);
    } catch (_) {}
  }

  void _wheelSetToken(String t, {bool notify = true}) {
    _wheelToken = t;
    _wheelPersistToken(t);
    if (notify) {
      for (final cb
      in List<void Function(String)>.from(_wheelWaiters)) {
        try {
          cb(t);
        } catch (e) {
          _wheelLog.wheelWarn('fcm waiter error: $e');
        }
      }
      _wheelWaiters.clear();
    }
  }

  Future<void> wheelWaitToken(
      Function(String token) onToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((_wheelToken ?? '').isNotEmpty) {
        onToken(_wheelToken!);
        return;
      }

      _wheelWaiters.add(onToken);
    } catch (e) {
      _wheelLog.wheelErr('wheelWaitToken error: $e');
    }
  }
}

// ============================================================================
// Рулеточный lightning loader (молния, которая блестит)
// ============================================================================

class WheelLightningLoader extends StatefulWidget {
  const WheelLightningLoader({Key? key}) : super(key: key);

  @override
  State<WheelLightningLoader> createState() =>
      _WheelLightningLoaderState();
}

class _WheelLightningLoaderState extends State<WheelLightningLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController wheelAnimationController;
  late Animation<double> wheelFlashAnimation;
  late Animation<double> wheelScaleAnimation;
  late Animation<double> wheelGlowAnimation;

  @override
  void initState() {
    super.initState();
    wheelAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    wheelFlashAnimation = CurvedAnimation(
      parent: wheelAnimationController,
      curve: Curves.easeInOut,
    );

    wheelScaleAnimation =
        Tween<double>(begin: 0.9, end: 1.15).animate(
          CurvedAnimation(
            parent: wheelAnimationController,
            curve: Curves.easeInOutCubic,
          ),
        );

    wheelGlowAnimation =
        Tween<double>(begin: 0.4, end: 1.0).animate(
          CurvedAnimation(
            parent: wheelAnimationController,
            curve: Curves.easeInOutSine,
          ),
        );
  }

  @override
  void dispose() {
    wheelAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size s = MediaQuery.of(context).size;
    final double h = s.height * 0.32;
    final double w = h * 0.45;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: wheelAnimationController,
        builder: (_, __) {
          final double opacity =
              0.5 + 0.5 * wheelFlashAnimation.value;

          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Фоновое свечение
                Container(
                  width: h * 1.8,
                  height: h * 1.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        Colors.yellowAccent
                            .withOpacity(0.0),
                        Colors.yellowAccent.withOpacity(
                            0.12 *
                                wheelGlowAnimation.value),
                        Colors.deepOrangeAccent
                            .withOpacity(0.18 *
                            wheelGlowAnimation.value),
                      ],
                      stops: const <double>[
                        0.4,
                        0.75,
                        1.0
                      ],
                    ),
                  ),
                ),
                // Молния
                Transform.scale(
                  scale: wheelScaleAnimation.value,
                  child: Opacity(
                    opacity: opacity,
                    child: CustomPaint(
                      size: Size(w, h),
                      painter: _WheelLightningPainter(
                        glow: wheelGlowAnimation.value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WheelLightningPainter extends CustomPainter {
  _WheelLightningPainter({required this.glow});
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Path bolt = Path()
      ..moveTo(w * 0.45, 0)
      ..lineTo(w * 0.15, h * 0.52)
      ..lineTo(w * 0.42, h * 0.52)
      ..lineTo(w * 0.28, h)
      ..lineTo(w * 0.75, h * 0.42)
      ..lineTo(w * 0.48, h * 0.42)
      ..close();

    final Paint mainPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0xFFFFF9C4),
          const Color(0xFFFFF176),
          const Color(0xFFFFD54F),
          const Color(0xFFFFB300),
        ],
      ).createShader(Offset.zero & size);

    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12
      ..maskFilter =
      MaskFilter.blur(BlurStyle.outer, 18 * glow)
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.yellowAccent
              .withOpacity(0.9 * glow),
          Colors.deepOrangeAccent
              .withOpacity(0.35 * glow),
          Colors.purpleAccent
              .withOpacity(0.15 * glow),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(w * 0.45, h * 0.45),
          radius: w,
        ),
      );

    final Paint highlightPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Colors.white.withOpacity(0.7 * glow),
          Colors.white.withOpacity(0.0),
        ],
        stops: const <double>[0.0, 0.5],
      ).createShader(Offset.zero & size);

    canvas.drawPath(bolt, strokePaint);
    canvas.drawPath(bolt, mainPaint);
    canvas.drawPath(bolt, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _WheelLightningPainter oldDelegate) {
    return oldDelegate.glow != glow;
  }
}

// ============================================================================
// Рулеточная статистика (аналог luckHunterPostStat)
// ============================================================================

Future<String> wheelFinalUrl(
    String wheelStartUrl, {
      int wheelMaxHops = 10,
    }) async {
  final httpClient = HttpClient();

  try {
    Uri currentUri = Uri.parse(wheelStartUrl);

    for (int i = 0; i < wheelMaxHops; i++) {
      final req = await httpClient.getUrl(currentUri);
      req.followRedirects = false;
      final resp = await req.close();

      if (resp.isRedirect) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (loc == null || loc.isEmpty) break;

        final nextUri = Uri.parse(loc);
        currentUri = nextUri.hasScheme
            ? nextUri
            : currentUri.resolveUri(nextUri);
        continue;
      }

      return currentUri.toString();
    }

    return currentUri.toString();
  } catch (e) {
    debugPrint('wheelFinalUrl error: $e');
    return wheelStartUrl;
  } finally {
    httpClient.close(force: true);
  }
}

Future<void> wheelPostStat({
  required String wheelEvent,
  required int wheelTimeStart,
  required String wheelUrl,
  required int wheelTimeFinish,
  required String wheelAppSid,
  int? wheelFirstPageTs,
}) async {
  try {
    final resolved = await wheelFinalUrl(wheelUrl);
    final payload = <String, dynamic>{
      'event': wheelEvent,
      'timestart': wheelTimeStart,
      'timefinsh': wheelTimeFinish,
      'url': resolved,
      'appleID': '6755681349',
      'open_count': '$wheelAppSid/$wheelTimeStart',
    };

    debugPrint('wheelStat $payload');

    final resp = await http.post(
      Uri.parse('$kWheelStatEndpoint/$wheelAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    debugPrint(
        'wheelStat resp=${resp.statusCode} body=${resp.body}');
  } catch (e) {
    debugPrint('wheelPostStat error: $e');
  }
}

// ============================================================================
// Виджет-стол с WebView — WheelTableView
// ============================================================================

class WheelTableView extends StatefulWidget
    with WidgetsBindingObserver {
  String wheelStartingLane;
  WheelTableView(this.wheelStartingLane, {super.key});

  @override
  State<WheelTableView> createState() =>
      _WheelTableViewState(wheelStartingLane);
}

class _WheelTableViewState extends State<WheelTableView>
    with WidgetsBindingObserver {
  _WheelTableViewState(this._wheelCurrentLane);

  final WheelVault _wheelVault = WheelVault();

  late InAppWebViewController _wheelWheelController;
  String? _wheelPushToken;
  final WheelDeviceDeck _wheelDeviceDeck = WheelDeviceDeck();
  final WheelSpy _wheelSpy = WheelSpy();

  bool _wheelOverlayBusy = false;
  String _wheelCurrentLane;
  DateTime? _wheelLastPausedAt;

  bool _wheelLoadedOnceSent = false;
  int? _wheelFirstPageTs;
  int _wheelStartLoadTs = 0;

  // Внешние “столы” (tg/wa/bnl и соцсети)
  final Set<String> _wheelExternalHosts = {
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> _wheelExternalSchemes = {
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(wheelBgDealer);

    _wheelFirstPageTs =
        DateTime.now().millisecondsSinceEpoch;

    _wheelInitPushAndGetToken();
    _wheelDeviceDeck.wheelInit();
    _wheelWireForegroundPushHandlers();
    _wheelBindPlatformNotificationTap();
    _wheelSpy.wheelStart(onWheelUpdate: () {
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState wheelState) {
    if (wheelState == AppLifecycleState.paused) {
      _wheelLastPausedAt = DateTime.now();
    }
    if (wheelState == AppLifecycleState.resumed) {
      if (Platform.isIOS && _wheelLastPausedAt != null) {
        final now = DateTime.now();
        final drift = now.difference(_wheelLastPausedAt!);
        if (drift > const Duration(minutes: 25)) {
          _wheelForceReloadToLobby();
        }
      }
      _wheelLastPausedAt = null;
    }
  }

  void _wheelForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => WheelTableView(_wheelCurrentLane),
        ),
            (route) => false,
      );
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------
  void _wheelWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage wheelMsg) {
      if (wheelMsg.data['uri'] != null) {
        _wheelNavigateTo(wheelMsg.data['uri'].toString());
      } else {
        _wheelReturnToCurrentLane();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage wheelMsg) {
      if (wheelMsg.data['uri'] != null) {
        _wheelNavigateTo(wheelMsg.data['uri'].toString());
      } else {
        _wheelReturnToCurrentLane();
      }
    });
  }

  void _wheelNavigateTo(String wheelNewLane) async {
    await _wheelWheelController.loadUrl(
      urlRequest: URLRequest(url: WebUri(wheelNewLane)),
    );
  }

  void _wheelReturnToCurrentLane() async {
    Future.delayed(const Duration(seconds: 3), () {
      _wheelWheelController.loadUrl(
        urlRequest: URLRequest(url: WebUri(_wheelCurrentLane)),
      );
    });
  }

  Future<void> _wheelInitPushAndGetToken() async {
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _wheelPushToken = await fm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------
  void _wheelBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall wheelCall) async {
      if (wheelCall.method == "onNotificationTap") {
        final Map<String, dynamic> wheelPayload =
        Map<String, dynamic>.from(
            wheelCall.arguments);
        debugPrint(
            "URI from platform tap: ${wheelPayload['uri']}");
        final wheelUri =
        wheelPayload["uri"]?.toString();
        if (wheelUri != null &&
            !wheelUri.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  WheelTableView(wheelUri),
            ),
                (route) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Повторная привязка — как в оригинале
    _wheelBindPlatformNotificationTap();

    final wheelIsDark =
        MediaQuery.of(context).platformBrightness ==
            Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wheelIsDark
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri(_wheelCurrentLane),
              ),
              onWebViewCreated:
                  (InAppWebViewController wheelController) {
                _wheelWheelController = wheelController;

                _wheelWheelController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (wheelArgs) {
                    _wheelVault.wheelWheel.wheelLog(
                        "JS Args: $wheelArgs");
                    try {
                      return wheelArgs.reduce(
                              (wheelV, wheelE) =>
                          wheelV + wheelE);
                    } catch (_) {
                      return wheelArgs.toString();
                    }
                  },
                );
              },
              onLoadStart:
                  (InAppWebViewController wheelController,
                  Uri? wheelUri) async {
                _wheelStartLoadTs =
                    DateTime.now().millisecondsSinceEpoch;

                if (wheelUri != null) {
                  if (WheelKit.wheelLooksLikeBareMail(
                      wheelUri)) {
                    try {
                      await wheelController.stopLoading();
                    } catch (_) {}
                    final wheelMailto =
                    WheelKit.wheelToMailto(wheelUri);
                    await WheelLinker.wheelOpen(
                        WheelKit.wheelGmailize(
                            wheelMailto));
                    return;
                  }

                  final wheelS =
                  wheelUri.scheme.toLowerCase();
                  if (wheelS != 'http' &&
                      wheelS != 'https') {
                    try {
                      await wheelController.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop:
                  (InAppWebViewController wheelController,
                  Uri? wheelUri) async {
                await wheelController.evaluateJavascript(
                  source:
                  "console.log('Hello from Roulette JS!');",
                );

                setState(() {
                  _wheelCurrentLane =
                      wheelUri?.toString() ??
                          _wheelCurrentLane;
                });

                Future.delayed(
                    const Duration(seconds: 20), () {
                  _wheelSendLoadedOnce();
                });
              },
              shouldOverrideUrlLoading:
                  (InAppWebViewController wheelController,
                  NavigationAction wheelNav) async {
                final wheelUri =
                    wheelNav.request.url;
                if (wheelUri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (WheelKit.wheelLooksLikeBareMail(
                    wheelUri)) {
                  final wheelMailto =
                  WheelKit.wheelToMailto(wheelUri);
                  await WheelLinker.wheelOpen(
                      WheelKit.wheelGmailize(
                          wheelMailto));
                  return NavigationActionPolicy.CANCEL;
                }

                final wheelSch =
                wheelUri.scheme.toLowerCase();

                if (wheelSch == 'mailto') {
                  await WheelLinker.wheelOpen(
                      WheelKit.wheelGmailize(
                          wheelUri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (wheelSch == 'tel') {
                  await launchUrl(
                    wheelUri,
                    mode: LaunchMode
                        .externalApplication,
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final wheelHost =
                wheelUri.host.toLowerCase();
                final bool isSocial =
                    wheelHost.endsWith('facebook.com') ||
                        wheelHost.endsWith(
                            'instagram.com') ||
                        wheelHost.endsWith(
                            'twitter.com') ||
                        wheelHost.endsWith('x.com');

                if (isSocial) {
                  await WheelLinker.wheelOpen(
                      wheelUri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (_wheelIsExternalTable(
                    wheelUri)) {
                  final mapped =
                  _wheelMapExternalToHttp(
                      wheelUri);
                  await WheelLinker.wheelOpen(
                      mapped);
                  return NavigationActionPolicy.CANCEL;
                }

                if (wheelSch != 'http' &&
                    wheelSch != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow:
                  (InAppWebViewController wheelController,
                  CreateWindowAction wheelReq) async {
                final wheelU =
                    wheelReq.request.url;
                if (wheelU == null) return false;

                if (WheelKit.wheelLooksLikeBareMail(
                    wheelU)) {
                  final wheelM =
                  WheelKit.wheelToMailto(wheelU);
                  await WheelLinker.wheelOpen(
                      WheelKit.wheelGmailize(
                          wheelM));
                  return false;
                }

                final wheelSch =
                wheelU.scheme.toLowerCase();

                if (wheelSch == 'mailto') {
                  await WheelLinker.wheelOpen(
                      WheelKit.wheelGmailize(
                          wheelU));
                  return false;
                }

                if (wheelSch == 'tel') {
                  await launchUrl(
                    wheelU,
                    mode: LaunchMode
                        .externalApplication,
                  );
                  return false;
                }

                final wheelHost =
                wheelU.host.toLowerCase();
                final bool isSocial =
                    wheelHost.endsWith('facebook.com') ||
                        wheelHost.endsWith(
                            'instagram.com') ||
                        wheelHost.endsWith(
                            'twitter.com') ||
                        wheelHost.endsWith('x.com');

                if (isSocial) {
                  await WheelLinker.wheelOpen(
                      wheelU);
                  return false;
                }

                if (_wheelIsExternalTable(
                    wheelU)) {
                  final mapped =
                  _wheelMapExternalToHttp(
                      wheelU);
                  await WheelLinker.wheelOpen(
                      mapped);
                  return false;
                }

                if (wheelSch == 'http' ||
                    wheelSch == 'https') {
                  wheelController.loadUrl(
                    urlRequest:
                    URLRequest(url: wheelU),
                  );
                }

                return false;
              },
            ),

            if (_wheelOverlayBusy)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: const Center(
                    child: WheelLightningLoader(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Рулеточные утилиты маршрутов (протоколы/внешние “столы”)
  // ========================================================================
  bool _wheelIsExternalTable(Uri wheelU) {
    final wheelSch = wheelU.scheme.toLowerCase();
    if (_wheelExternalSchemes.contains(wheelSch)) {
      return true;
    }

    if (wheelSch == 'http' || wheelSch == 'https') {
      final wheelH = wheelU.host.toLowerCase();
      if (_wheelExternalHosts.contains(wheelH)) {
        return true;
      }
      if (wheelH.endsWith('t.me')) return true;
      if (wheelH.endsWith('wa.me')) return true;
      if (wheelH.endsWith('m.me')) return true;
      if (wheelH.endsWith('signal.me')) return true;
      if (wheelH.endsWith('facebook.com')) return true;
      if (wheelH.endsWith('instagram.com')) return true;
      if (wheelH.endsWith('twitter.com')) return true;
      if (wheelH.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri _wheelMapExternalToHttp(Uri wheelU) {
    final wheelSch = wheelU.scheme.toLowerCase();

    if (wheelSch == 'tg' || wheelSch == 'telegram') {
      final wheelQp = wheelU.queryParameters;
      final wheelDomain = wheelQp['domain'];
      if (wheelDomain != null && wheelDomain.isNotEmpty) {
        return Uri.https('t.me', '/$wheelDomain', {
          if (wheelQp['start'] != null)
            'start': wheelQp['start']!,
        });
      }
      final wheelPath =
      wheelU.path.isNotEmpty ? wheelU.path : '';
      return Uri.https(
        't.me',
        '/$wheelPath',
        wheelU.queryParameters.isEmpty
            ? null
            : wheelU.queryParameters,
      );
    }

    if (wheelSch == 'whatsapp') {
      final wheelQp = wheelU.queryParameters;
      final wheelPhone = wheelQp['phone'];
      final wheelText = wheelQp['text'];
      if (wheelPhone != null && wheelPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${WheelKit.wheelJustDigits(wheelPhone)}',
          {
            if (wheelText != null && wheelText.isNotEmpty)
              'text': wheelText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        {
          if (wheelText != null && wheelText.isNotEmpty)
            'text': wheelText,
        },
      );
    }

    if (wheelSch == 'bnl') {
      final wheelNewPath =
      wheelU.path.isNotEmpty ? wheelU.path : '';
      return Uri.https(
        'bnl.com',
        '/$wheelNewPath',
        wheelU.queryParameters.isEmpty
            ? null
            : wheelU.queryParameters,
      );
    }

    return wheelU;
  }

  Future<void> _wheelSendLoadedOnce() async {
    if (_wheelLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await wheelPostStat(
      wheelEvent: 'Loaded',
      wheelTimeStart: _wheelStartLoadTs,
      wheelTimeFinish: now,
      wheelUrl: _wheelCurrentLane,
      wheelAppSid: _wheelSpy.wheelAfUid,
      wheelFirstPageTs: _wheelFirstPageTs,
    );

    _wheelLoadedOnceSent = true;
  }
}