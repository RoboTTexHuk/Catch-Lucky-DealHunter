import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;
import 'dart:math' as _hunter_math;
import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, SystemChrome, SystemUiOverlayStyle, MethodCall;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:luckcatch/pushHunter.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

// ============================================================================
// Константы
// ============================================================================
const String kNeonCinemaLoadedOnceKey = 'loaded_once';
const String kNeonCinemaStatEndpoint = 'https://api.saleclearens.store/stat';
const String kNeonCinemaCachedFcmKey = 'cached_fcm';

// ============================================================================
// Лёгкие сервисы (без provider/riverpod/secure_storage/logger)
// ============================================================================

class LuckHunterBarrel {
  static final LuckHunterBarrel luckHunterInstance = LuckHunterBarrel._internal();

  LuckHunterBarrel._internal();

  factory LuckHunterBarrel() => luckHunterInstance;

  final Connectivity luckHunterConnectivity = Connectivity();

  void luckHunterLogInfo(Object luckHunterMessage) =>
      debugPrint('[I] $luckHunterMessage');
  void luckHunterLogWarn(Object luckHunterMessage) =>
      debugPrint('[W] $luckHunterMessage');
  void luckHunterLogError(Object luckHunterMessage) =>
      debugPrint('[E] $luckHunterMessage');
}

// ============================================================================
// Сеть/данные: NeonCinemaWire -> LuckHunterWire
// ============================================================================

class LuckHunterWire {
  final LuckHunterBarrel _luckHunterBarrel = LuckHunterBarrel();

  Future<bool> isLuckHunterOnline() async {
    final ConnectivityResult luckHunterConnectivityResult =
    await _luckHunterBarrel.luckHunterConnectivity.checkConnectivity();
    return luckHunterConnectivityResult != ConnectivityResult.none;
  }

  Future<void> postLuckHunterJson(
      String luckHunterUrl,
      Map<String, dynamic> luckHunterData,
      ) async {
    try {
      await http.post(
        Uri.parse(luckHunterUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(luckHunterData),
      );
    } catch (luckHunterError) {
      _luckHunterBarrel
          .luckHunterLogError('postGlowJson error: $luckHunterError');
    }
  }
}

// ============================================================================
// Досье устройства: NeonCinemaDeck -> LuckHunterDeviceDeck
// ============================================================================

class LuckHunterDeviceDeck {
  String? luckHunterDeviceId;
  String? luckHunterSessionId = 'roulette-one-off';
  String? luckHunterPlatformName; // android/ios
  String? luckHunterOsVersion;
  String? luckHunterAppVersion;
  String? luckHunterLang;
  String? luckHunterTimezoneName;
  bool luckHunterPushEnabled = true;

  Future<void> initLuckHunterDeviceDeck() async {
    final DeviceInfoPlugin luckHunterDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo luckHunterAndroidInfo =
      await luckHunterDeviceInfoPlugin.androidInfo;
      luckHunterDeviceId = luckHunterAndroidInfo.id;
      luckHunterPlatformName = 'android';
      luckHunterOsVersion = luckHunterAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo luckHunterIosInfo =
      await luckHunterDeviceInfoPlugin.iosInfo;
      luckHunterDeviceId = luckHunterIosInfo.identifierForVendor;
      luckHunterPlatformName = 'ios';
      luckHunterOsVersion = luckHunterIosInfo.systemVersion;
    }

    final PackageInfo luckHunterPackageInfo =
    await PackageInfo.fromPlatform();
    luckHunterAppVersion = luckHunterPackageInfo.version;
    luckHunterLang = Platform.localeName.split('_').first;
    luckHunterTimezoneName = tz_zone.local.name;
    luckHunterSessionId =
    'roulette-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> asLuckHunterMap({String? luckHunterFcm}) => {
    'fcm_token': luckHunterFcm ?? 'missing_token',
    'device_id': luckHunterDeviceId ?? 'missing_id',
    'app_name': 'bestoffers',
    'instance_id': luckHunterSessionId ?? 'missing_session',
    'platform': luckHunterPlatformName ?? 'missing_system',
    'os_version': luckHunterOsVersion ?? 'missing_build',
    'app_version': luckHunterAppVersion ?? 'missing_app',
    'language': luckHunterLang ?? 'en',
    'timezone': luckHunterTimezoneName ?? 'UTC',
    'push_enabled': luckHunterPushEnabled,
  };
}

// ============================================================================
// AppsFlyer: NeonCinemaSpy -> LuckHunterSpy
// ============================================================================

class LuckHunterSpy {
  af_core.AppsFlyerOptions? luckHunterOptions;
  af_core.AppsflyerSdk? luckHunterSdk;

  String luckHunterAfUid = '';
  String luckHunterAfData = '';

  void startLuckHunterSpy({VoidCallback? onLuckHunterUpdate}) {
    final af_core.AppsFlyerOptions luckHunterConfig =
    af_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    luckHunterOptions = luckHunterConfig;
    luckHunterSdk = af_core.AppsflyerSdk(luckHunterConfig);

    luckHunterSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    luckHunterSdk?.startSDK(
      onSuccess: () =>
          LuckHunterBarrel().luckHunterLogInfo('NeonCinemaSpy started'),
      onError: (luckHunterCode, luckHunterMsg) =>
          LuckHunterBarrel().luckHunterLogError(
              'NeonCinemaSpy error $luckHunterCode: $luckHunterMsg'),
    );

    luckHunterSdk?.onInstallConversionData((luckHunterValue) {
      luckHunterAfData = luckHunterValue.toString();
      onLuckHunterUpdate?.call();
    });

    luckHunterSdk?.getAppsFlyerUID().then((luckHunterValue) {
      luckHunterAfUid = luckHunterValue.toString();
      onLuckHunterUpdate?.call();
    });
  }
}

// ============================================================================
// Новый loader: вместо диско-шара — блистающая молния
// ============================================================================

class LuckHunterLightningLoader extends StatefulWidget {
  const LuckHunterLightningLoader({Key? key}) : super(key: key);

  @override
  State<LuckHunterLightningLoader> createState() =>
      _LuckHunterLightningLoaderState();
}

class _LuckHunterLightningLoaderState extends State<LuckHunterLightningLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController luckHunterAnimationController;
  late Animation<double> luckHunterFlashAnimation;
  late Animation<double> luckHunterScaleAnimation;
  late Animation<double> luckHunterGlowAnimation;

  @override
  void initState() {
    super.initState();
    luckHunterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    luckHunterFlashAnimation =
        CurvedAnimation(parent: luckHunterAnimationController, curve: Curves.easeInOut);

    luckHunterScaleAnimation =
        Tween<double>(begin: 0.9, end: 1.15).animate(
          CurvedAnimation(
            parent: luckHunterAnimationController,
            curve: Curves.easeInOutCubic,
          ),
        );

    luckHunterGlowAnimation =
        Tween<double>(begin: 0.4, end: 1.0).animate(
          CurvedAnimation(
            parent: luckHunterAnimationController,
            curve: Curves.easeInOutSine,
          ),
        );
  }

  @override
  void dispose() {
    luckHunterAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size luckHunterSize = MediaQuery.of(context).size;
    final double luckHunterLightningHeight = luckHunterSize.height * 0.32;
    final double luckHunterLightningWidth = luckHunterLightningHeight * 0.45;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: luckHunterAnimationController,
        builder: (BuildContext context, Widget? child) {
          final double luckHunterOpacity = 0.5 + 0.5 * luckHunterFlashAnimation.value;

          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Фоновой радиальный "всплеск"
                Container(
                  width: luckHunterLightningHeight * 1.8,
                  height: luckHunterLightningHeight * 1.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        Colors.yellowAccent.withOpacity(0.0),
                        Colors.yellowAccent.withOpacity(0.12 * luckHunterGlowAnimation.value),
                        Colors.deepOrangeAccent.withOpacity(0.18 * luckHunterGlowAnimation.value),
                      ],
                      stops: const <double>[0.4, 0.75, 1.0],
                    ),
                  ),
                ),
                // Сам силуэт молнии с блеском
                Transform.scale(
                  scale: luckHunterScaleAnimation.value,
                  child: Opacity(
                    opacity: luckHunterOpacity,
                    child: CustomPaint(
                      size: Size(
                        luckHunterLightningWidth,
                        luckHunterLightningHeight,
                      ),
                      painter: _LuckHunterLightningPainter(
                        glow: luckHunterGlowAnimation.value,
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

class _LuckHunterLightningPainter extends CustomPainter {
  _LuckHunterLightningPainter({required this.glow});

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    final Path bolt = Path()
      ..moveTo(width * 0.45, 0)
      ..lineTo(width * 0.15, height * 0.52)
      ..lineTo(width * 0.42, height * 0.52)
      ..lineTo(width * 0.28, height)
      ..lineTo(width * 0.75, height * 0.42)
      ..lineTo(width * 0.48, height * 0.42)
      ..close();

    // Основной жёлтый "тело" молнии
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

    // Обводка с неоновым эффектом
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.12
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, 18 * glow)
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.yellowAccent.withOpacity(0.9 * glow),
          Colors.deepOrangeAccent.withOpacity(0.35 * glow),
          Colors.purpleAccent.withOpacity(0.15 * glow),
        ],
      ).createShader(Offset(width * 0.45, height * 0.45) & size);

    // Дополнительный "блик"
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

    // Сначала свечение, потом тело молнии, сверху — бликовый слой
    canvas.drawPath(bolt, strokePaint);
    canvas.drawPath(bolt, mainPaint);
    canvas.drawPath(bolt, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _LuckHunterLightningPainter oldDelegate) {
    return oldDelegate.glow != glow;
  }
}

// ============================================================================
// FCM фоновые крики
// ============================================================================

@pragma('vm:entry-point')
Future<void> luckHunterFcmBackgroundHandler(RemoteMessage luckHunterMessage) async {
  LuckHunterBarrel()
      .luckHunterLogInfo('bg-fcm: ${luckHunterMessage.messageId}');
  LuckHunterBarrel()
      .luckHunterLogInfo('bg-data: ${luckHunterMessage.data}');
}

// ============================================================================
// Мост для получения токена через нативный канал: NeonCinemaFcmBridge -> LuckHunterFcmBridge
// ============================================================================

class LuckHunterFcmBridge {
  final LuckHunterBarrel _luckHunterBarrel = LuckHunterBarrel();
  String? _luckHunterToken;
  final List<void Function(String)> _luckHunterWaiters = <void Function(String)>[];

  String? get luckHunterToken => _luckHunterToken;

  LuckHunterFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall luckHunterCall) async {
      if (luckHunterCall.method == 'setToken') {
        final String luckHunterTokenString =
        luckHunterCall.arguments as String;
        if (luckHunterTokenString.isNotEmpty) {
          _setLuckHunterToken(luckHunterTokenString);
        }
      }
    });

    _restoreLuckHunterToken();
  }

  Future<void> _restoreLuckHunterToken() async {
    try {
      final SharedPreferences luckHunterPrefs =
      await SharedPreferences.getInstance();
      final String? luckHunterCachedToken =
      luckHunterPrefs.getString(kNeonCinemaCachedFcmKey);
      if (luckHunterCachedToken != null &&
          luckHunterCachedToken.isNotEmpty) {
        _setLuckHunterToken(luckHunterCachedToken, notify: false);
      }
    } catch (_) {}
  }

  Future<void> _persistLuckHunterToken(String luckHunterNewToken) async {
    try {
      final SharedPreferences luckHunterPrefs =
      await SharedPreferences.getInstance();
      await luckHunterPrefs.setString(
          kNeonCinemaCachedFcmKey, luckHunterNewToken);
    } catch (_) {}
  }

  void _setLuckHunterToken(String luckHunterNewToken,
      {bool notify = true}) {
    _luckHunterToken = luckHunterNewToken;
    _persistLuckHunterToken(luckHunterNewToken);
    if (notify) {
      for (final void Function(String) luckHunterCallback
      in List<void Function(String)>.from(_luckHunterWaiters)) {
        try {
          luckHunterCallback(luckHunterNewToken);
        } catch (luckHunterError) {
          _luckHunterBarrel
              .luckHunterLogWarn('fcm waiter error: $luckHunterError');
        }
      }
      _luckHunterWaiters.clear();
    }
  }

  Future<void> waitLuckHunterToken(
      Function(String luckHunterToken) onLuckHunterToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((_luckHunterToken ?? '').isNotEmpty) {
        onLuckHunterToken(_luckHunterToken!);
        return;
      }

      _luckHunterWaiters.add(onLuckHunterToken);
    } catch (luckHunterError) {
      _luckHunterBarrel.luckHunterLogError(
          'waitGlowToken error: $luckHunterError');
    }
  }
}

// ============================================================================
// Вестибюль (Splash): теперь с молнией
// ============================================================================

class LuckHunterHall extends StatefulWidget {
  const LuckHunterHall({Key? key}) : super(key: key);

  @override
  State<LuckHunterHall> createState() => _LuckHunterHallState();
}

class _LuckHunterHallState extends State<LuckHunterHall> {
  final LuckHunterFcmBridge luckHunterFcmBridge = LuckHunterFcmBridge();
  bool luckHunterNavigatedOnce = false;
  Timer? luckHunterFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    luckHunterFcmBridge
        .waitLuckHunterToken((String luckHunterTokenValue) {
      _goLuckHunterHarbor(luckHunterTokenValue);
    });

    luckHunterFallbackTimer =
        Timer(const Duration(seconds: 8), () => _goLuckHunterHarbor(''));
  }

  void _goLuckHunterHarbor(String luckHunterSignal) {
    if (luckHunterNavigatedOnce) return;
    luckHunterNavigatedOnce = true;
    luckHunterFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext luckHunterContext) =>
            LuckHunterHarbor(luckHunterSignal: luckHunterSignal),
      ),
    );
  }

  @override
  void dispose() {
    luckHunterFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: LuckHunterLightningLoader(),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class LuckHunterBosun {
  final LuckHunterDeviceDeck luckHunterDeviceDeck;
  final LuckHunterSpy luckHunterSpy;

  LuckHunterBosun({
    required this.luckHunterDeviceDeck,
    required this.luckHunterSpy,
  });

  Map<String, dynamic> luckHunterDeviceMap(String? luckHunterToken) =>
      luckHunterDeviceDeck.asLuckHunterMap(luckHunterFcm: luckHunterToken);

  Map<String, dynamic> luckHunterAfMap(String? luckHunterToken) => {
    'content': {
      'af_data': luckHunterSpy.luckHunterAfData,
      'af_id': luckHunterSpy.luckHunterAfUid,
      'fb_app_name': 'bestoffers',
      'app_name': 'bestoffers',
      'deep': null,
      'bundle_identifier': 'com.luckcuthc.luckcatch',
      'app_version': '1.0.0',
      'apple_id': '6756072063',
      'fcm_token': luckHunterToken ?? 'no_token',
      'device_id': luckHunterDeviceDeck.luckHunterDeviceId ?? 'no_device',
      'instance_id':
      luckHunterDeviceDeck.luckHunterSessionId ?? 'no_instance',
      'platform':
      luckHunterDeviceDeck.luckHunterPlatformName ?? 'no_type',
      'os_version':
      luckHunterDeviceDeck.luckHunterOsVersion ?? 'no_os',
      'app_version':
      luckHunterDeviceDeck.luckHunterAppVersion ?? 'no_app',
      'language':
      luckHunterDeviceDeck.luckHunterLang ?? 'en',
      'timezone':
      luckHunterDeviceDeck.luckHunterTimezoneName ?? 'UTC',
      'push_enabled':
      luckHunterDeviceDeck.luckHunterPushEnabled,
      'useruid': luckHunterSpy.luckHunterAfUid,
    },
  };
}

class LuckHunterCourier {
  final LuckHunterBosun luckHunterBosun;
  final InAppWebViewController Function() getLuckHunterWebView;

  LuckHunterCourier({
    required this.luckHunterBosun,
    required this.getLuckHunterWebView,
  });

  Future<void> putLuckHunterDeviceToLocalStorage(
      String? luckHunterToken) async {
    final Map<String, dynamic> luckHunterMap =
    luckHunterBosun.luckHunterDeviceMap(luckHunterToken);
    await getLuckHunterWebView().evaluateJavascript(
      source:
      '''
localStorage.setItem('app_data', JSON.stringify(${jsonEncode(luckHunterMap)}));
''',
    );
  }

  Future<void> sendLuckHunterRawToPage(String? luckHunterToken) async {
    final Map<String, dynamic> luckHunterPayload =
    luckHunterBosun.luckHunterAfMap(luckHunterToken);
    final String luckHunterJsonString =
    jsonEncode(luckHunterPayload);

    print('load stry' + luckHunterJsonString.toString());
    LuckHunterBarrel()
        .luckHunterLogInfo('SendGlowRawData: $luckHunterJsonString');

    await getLuckHunterWebView().evaluateJavascript(
      source:
      'sendRawData(${jsonEncode(luckHunterJsonString)});',
    );
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================

Future<String> luckHunterFinalUrl(
    String luckHunterStartUrl, {
      int luckHunterMaxHops = 10,
    }) async {
  final HttpClient luckHunterHttpClient = HttpClient();

  try {
    Uri luckHunterCurrentUri = Uri.parse(luckHunterStartUrl);

    for (int luckHunterIndex = 0;
    luckHunterIndex < luckHunterMaxHops;
    luckHunterIndex++) {
      final HttpClientRequest luckHunterRequest =
      await luckHunterHttpClient.getUrl(luckHunterCurrentUri);
      luckHunterRequest.followRedirects = false;
      final HttpClientResponse luckHunterResponse =
      await luckHunterRequest.close();

      if (luckHunterResponse.isRedirect) {
        final String? luckHunterLocationHeader =
        luckHunterResponse.headers.value(HttpHeaders.locationHeader);
        if (luckHunterLocationHeader == null ||
            luckHunterLocationHeader.isEmpty) {
          break;
        }

        final Uri luckHunterNextUri =
        Uri.parse(luckHunterLocationHeader);
        luckHunterCurrentUri = luckHunterNextUri.hasScheme
            ? luckHunterNextUri
            : luckHunterCurrentUri.resolveUri(luckHunterNextUri);
        continue;
      }

      return luckHunterCurrentUri.toString();
    }

    return luckHunterCurrentUri.toString();
  } catch (luckHunterError) {
    debugPrint('neonCinemaFinalUrl error: $luckHunterError');
    return luckHunterStartUrl;
  } finally {
    luckHunterHttpClient.close(force: true);
  }
}

Future<void> luckHunterPostStat({
  required String luckHunterEvent,
  required int luckHunterTimeStart,
  required String luckHunterUrl,
  required int luckHunterTimeFinish,
  required String luckHunterAppSid,
  int? luckHunterFirstPageLoadTs,
}) async {
  try {
    final String luckHunterResolvedUrl =
    await luckHunterFinalUrl(luckHunterUrl);

    final Map<String, dynamic> luckHunterPayload = <String, dynamic>{
      'event': luckHunterEvent,
      'timestart': luckHunterTimeStart,
      'timefinsh': luckHunterTimeFinish,
      'url': luckHunterResolvedUrl,
      'appleID': '6756072063',
      'open_count': '$luckHunterAppSid/$luckHunterTimeStart',
    };

    debugPrint('neonCinemaStat $luckHunterPayload');

    final http.Response luckHunterResponse = await http.post(
      Uri.parse('$kNeonCinemaStatEndpoint/$luckHunterAppSid'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(luckHunterPayload),
    );

    debugPrint(
        'neonCinemaStat resp=${luckHunterResponse.statusCode} body=${luckHunterResponse.body}');
  } catch (luckHunterError) {
    debugPrint('neonCinemaPostStat error: $luckHunterError');
  }
}

// ============================================================================
// Главный WebView — LuckHunterHarbor
// ============================================================================

class LuckHunterHarbor extends StatefulWidget {
  final String? luckHunterSignal;

  const LuckHunterHarbor({super.key, required this.luckHunterSignal});

  @override
  State<LuckHunterHarbor> createState() => _LuckHunterHarborState();
}

class _LuckHunterHarborState extends State<LuckHunterHarbor>
    with WidgetsBindingObserver {
  late InAppWebViewController luckHunterWebViewController;
  final String luckHunterHomeUrl = 'https://api.saleclearens.store/';

  int luckHunterHatchCounter = 0;
  DateTime? luckHunterSleepAt;
  bool luckHunterVeilVisible = false;
  double luckHunterWarmProgress = 0.0;
  late Timer luckHunterWarmTimer;
  final int luckHunterWarmSeconds = 6;
  bool luckHunterCoverVisible = true;

  bool luckHunterLoadedOnceSent = false;
  int? luckHunterFirstPageTimestamp;

  LuckHunterCourier? luckHunterCourier;
  LuckHunterBosun? luckHunterBosun;

  String luckHunterCurrentUrl = '';
  int luckHunterStartLoadTimestamp = 0;

  final LuckHunterDeviceDeck luckHunterDeviceDeck = LuckHunterDeviceDeck();
  final LuckHunterSpy luckHunterSpy = LuckHunterSpy();

  final Set<String> luckHunterSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> luckHunterExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com',
    'www.bnl.com',
    // Новые соцсети
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    luckHunterFirstPageTimestamp =
        DateTime.now().millisecondsSinceEpoch;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          luckHunterCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        luckHunterVeilVisible = true;
      });
    });

    _bootLuckHunter();
  }

  Future<void> _loadLuckHunterLoadedFlag() async {
    final SharedPreferences luckHunterPrefs =
    await SharedPreferences.getInstance();
    luckHunterLoadedOnceSent =
        luckHunterPrefs.getBool(kNeonCinemaLoadedOnceKey) ?? false;
  }

  Future<void> _saveLuckHunterLoadedFlag() async {
    final SharedPreferences luckHunterPrefs =
    await SharedPreferences.getInstance();
    await luckHunterPrefs.setBool(kNeonCinemaLoadedOnceKey, true);
    luckHunterLoadedOnceSent = true;
  }

  Future<void> sendLuckHunterLoadedOnce({
    required String luckHunterUrl,
    required int luckHunterTimestart,
  }) async {
    if (luckHunterLoadedOnceSent) {
      debugPrint('Loaded already sent, skip');
      return;
    }

    final int luckHunterNow = DateTime.now().millisecondsSinceEpoch;

    await luckHunterPostStat(
      luckHunterEvent: 'Loaded',
      luckHunterTimeStart: luckHunterTimestart,
      luckHunterTimeFinish: luckHunterNow,
      luckHunterUrl: luckHunterUrl,
      luckHunterAppSid: luckHunterSpy.luckHunterAfUid,
      luckHunterFirstPageLoadTs: luckHunterFirstPageTimestamp,
    );

    await _saveLuckHunterLoadedFlag();
  }

  void _bootLuckHunter() {
    _startLuckHunterWarmProgress();
    _wireLuckHunterFcm();
    luckHunterSpy.startLuckHunterSpy(
      onLuckHunterUpdate: () => setState(() {}),
    );
    _bindLuckHunterNotificationTap();
    _prepareLuckHunterDeck();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await _pushLuckHunterDevice();
      await _pushLuckHunterAfData();
    });
  }

  void _wireLuckHunterFcm() {
    FirebaseMessaging.onMessage.listen((RemoteMessage luckHunterMessage) {
      final dynamic luckHunterLink = luckHunterMessage.data['uri'];
      if (luckHunterLink != null) {
        _navigateLuckHunter(luckHunterLink.toString());
      } else {
        _resetLuckHunterHome();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage luckHunterMessage) {
      final dynamic luckHunterLink = luckHunterMessage.data['uri'];
      if (luckHunterLink != null) {
        _navigateLuckHunter(luckHunterLink.toString());
      } else {
        _resetLuckHunterHome();
      }
    });
  }

  void _bindLuckHunterNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall luckHunterCall) async {
      if (luckHunterCall.method == 'onNotificationTap') {
        final Map<String, dynamic> luckHunterPayload =
        Map<String, dynamic>.from(luckHunterCall.arguments);
        if (luckHunterPayload['uri'] != null &&
            !luckHunterPayload['uri']
                .toString()
                .contains('Нет URI')) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext luckHunterContext) =>
                  WheelTableView(
                      luckHunterPayload['uri'].toString()),
            ),
                (Route<dynamic> luckHunterRoute) => false,
          );
        }
      }
    });
  }

  Future<void> _prepareLuckHunterDeck() async {
    try {
      await luckHunterDeviceDeck.initLuckHunterDeviceDeck();
      await _askLuckHunterPushPermissions();

      luckHunterBosun = LuckHunterBosun(
        luckHunterDeviceDeck: luckHunterDeviceDeck,
        luckHunterSpy: luckHunterSpy,
      );

      luckHunterCourier = LuckHunterCourier(
        luckHunterBosun: luckHunterBosun!,
        getLuckHunterWebView: () => luckHunterWebViewController,
      );

      await _loadLuckHunterLoadedFlag();
    } catch (luckHunterError) {
      LuckHunterBarrel()
          .luckHunterLogError('prepare fail: $luckHunterError');
    }
  }

  Future<void> _askLuckHunterPushPermissions() async {
    final FirebaseMessaging luckHunterMessaging =
        FirebaseMessaging.instance;
    await luckHunterMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void _navigateLuckHunter(String luckHunterLink) async {
    try {
      await luckHunterWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(luckHunterLink)),
      );
    } catch (luckHunterError) {
      LuckHunterBarrel()
          .luckHunterLogError('navigate error: $luckHunterError');
    }
  }

  void _resetLuckHunterHome() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        luckHunterWebViewController.loadUrl(
          urlRequest: URLRequest(url: WebUri(luckHunterHomeUrl)),
        );
      } catch (_) {}
    });
  }

  Future<void> _pushLuckHunterDevice() async {
    LuckHunterBarrel()
        .luckHunterLogInfo('TOKEN ship ${widget.luckHunterSignal}');
    try {
      await luckHunterCourier
          ?.putLuckHunterDeviceToLocalStorage(widget.luckHunterSignal);
    } catch (luckHunterError) {
      LuckHunterBarrel()
          .luckHunterLogError('pushGlowDevice error: $luckHunterError');
    }
  }

  Future<void> _pushLuckHunterAfData() async {
    try {
      await luckHunterCourier
          ?.sendLuckHunterRawToPage(widget.luckHunterSignal);
    } catch (luckHunterError) {
      LuckHunterBarrel()
          .luckHunterLogError('pushGlowAf error: $luckHunterError');
    }
  }

  void _startLuckHunterWarmProgress() {
    int luckHunterTick = 0;
    luckHunterWarmProgress = 0.0;

    luckHunterWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer luckHunterTimer) {
          if (!mounted) return;

          setState(() {
            luckHunterTick++;
            luckHunterWarmProgress =
                luckHunterTick / (luckHunterWarmSeconds * 10);

            if (luckHunterWarmProgress >= 1.0) {
              luckHunterWarmProgress = 1.0;
              luckHunterWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState luckHunterState) {
    if (luckHunterState == AppLifecycleState.paused) {
      luckHunterSleepAt = DateTime.now();
    }

    if (luckHunterState == AppLifecycleState.resumed) {
      if (Platform.isIOS && luckHunterSleepAt != null) {
        final DateTime luckHunterNow = DateTime.now();
        final Duration luckHunterDrift =
        luckHunterNow.difference(luckHunterSleepAt!);

        if (luckHunterDrift > const Duration(minutes: 25)) {
          reboardLuckHunter();
        }
      }
      luckHunterSleepAt = null;
    }
  }

  void reboardLuckHunter() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext luckHunterContext) =>
              LuckHunterHarbor(
                luckHunterSignal: widget.luckHunterSignal,
              ),
        ),
            (Route<dynamic> luckHunterRoute) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    luckHunterWarmTimer.cancel();
    super.dispose();
  }

  // ================== URL helpers ==================

  bool _isLuckHunterBareEmail(Uri luckHunterUri) {
    final String luckHunterScheme = luckHunterUri.scheme;
    if (luckHunterScheme.isNotEmpty) return false;
    final String luckHunterRaw = luckHunterUri.toString();
    return luckHunterRaw.contains('@') &&
        !luckHunterRaw.contains(' ');
  }

  Uri _toLuckHunterMailto(Uri luckHunterUri) {
    final String luckHunterFull = luckHunterUri.toString();
    final List<String> luckHunterParts = luckHunterFull.split('?');
    final String luckHunterEmail = luckHunterParts.first;
    final Map<String, String> luckHunterQueryParams =
    luckHunterParts.length > 1
        ? Uri.splitQueryString(luckHunterParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: luckHunterEmail,
      queryParameters:
      luckHunterQueryParams.isEmpty ? null : luckHunterQueryParams,
    );
  }

  bool _isLuckHunterPlatformish(Uri luckHunterUri) {
    final String luckHunterScheme =
    luckHunterUri.scheme.toLowerCase();
    if (luckHunterSchemes.contains(luckHunterScheme)) {
      return true;
    }

    if (luckHunterScheme == 'http' ||
        luckHunterScheme == 'https') {
      final String luckHunterHost =
      luckHunterUri.host.toLowerCase();

      if (luckHunterExternalHosts.contains(luckHunterHost)) {
        return true;
      }

      if (luckHunterHost.endsWith('t.me')) return true;
      if (luckHunterHost.endsWith('wa.me')) return true;
      if (luckHunterHost.endsWith('m.me')) return true;
      if (luckHunterHost.endsWith('signal.me')) return true;
      if (luckHunterHost.endsWith('facebook.com')) return true;
      if (luckHunterHost.endsWith('instagram.com')) return true;
      if (luckHunterHost.endsWith('twitter.com')) return true;
      if (luckHunterHost.endsWith('x.com')) return true;
    }

    return false;
  }

  String _luckHunterDigitsOnly(String luckHunterSource) =>
      luckHunterSource.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri _luckHunterHttpize(Uri luckHunterUri) {
    final String luckHunterScheme =
    luckHunterUri.scheme.toLowerCase();

    if (luckHunterScheme == 'tg' ||
        luckHunterScheme == 'telegram') {
      final Map<String, String> luckHunterQp =
          luckHunterUri.queryParameters;
      final String? luckHunterDomain = luckHunterQp['domain'];

      if (luckHunterDomain != null && luckHunterDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$luckHunterDomain',
          <String, String>{
            if (luckHunterQp['start'] != null)
              'start': luckHunterQp['start']!,
          },
        );
      }

      final String luckHunterPath =
      luckHunterUri.path.isNotEmpty ? luckHunterUri.path : '';

      return Uri.https(
        't.me',
        '/$luckHunterPath',
        luckHunterUri.queryParameters.isEmpty
            ? null
            : luckHunterUri.queryParameters,
      );
    }

    if ((luckHunterScheme == 'http' ||
        luckHunterScheme == 'https') &&
        luckHunterUri.host.toLowerCase().endsWith('t.me')) {
      return luckHunterUri;
    }

    if (luckHunterScheme == 'viber') {
      return luckHunterUri;
    }

    if (luckHunterScheme == 'whatsapp') {
      final Map<String, String> luckHunterQp =
          luckHunterUri.queryParameters;
      final String? luckHunterPhone = luckHunterQp['phone'];
      final String? luckHunterText = luckHunterQp['text'];

      if (luckHunterPhone != null &&
          luckHunterPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${_luckHunterDigitsOnly(luckHunterPhone)}',
          <String, String>{
            if (luckHunterText != null && luckHunterText.isNotEmpty)
              'text': luckHunterText,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (luckHunterText != null && luckHunterText.isNotEmpty)
            'text': luckHunterText,
        },
      );
    }

    if ((luckHunterScheme == 'http' ||
        luckHunterScheme == 'https') &&
        (luckHunterUri.host.toLowerCase().endsWith('wa.me') ||
            luckHunterUri.host
                .toLowerCase()
                .endsWith('whatsapp.com'))) {
      return luckHunterUri;
    }

    if (luckHunterScheme == 'skype') {
      return luckHunterUri;
    }

    if (luckHunterScheme == 'fb-messenger') {
      final String luckHunterPath =
      luckHunterUri.pathSegments.isNotEmpty
          ? luckHunterUri.pathSegments.join('/')
          : '';
      final Map<String, String> luckHunterQp =
          luckHunterUri.queryParameters;

      final String luckHunterId =
          luckHunterQp['id'] ??
              luckHunterQp['user'] ??
              luckHunterPath;

      if (luckHunterId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$luckHunterId',
          luckHunterUri.queryParameters.isEmpty
              ? null
              : luckHunterUri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        luckHunterUri.queryParameters.isEmpty
            ? null
            : luckHunterUri.queryParameters,
      );
    }

    if (luckHunterScheme == 'sgnl') {
      final Map<String, String> luckHunterQp =
          luckHunterUri.queryParameters;
      final String? luckHunterPhone = luckHunterQp['phone'];
      final String? luckHunterUsername = luckHunterQp['username'];

      if (luckHunterPhone != null &&
          luckHunterPhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${_luckHunterDigitsOnly(luckHunterPhone)}',
        );
      }

      if (luckHunterUsername != null &&
          luckHunterUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$luckHunterUsername',
        );
      }

      final String luckHunterPath =
      luckHunterUri.pathSegments.join('/');
      if (luckHunterPath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$luckHunterPath',
          luckHunterUri.queryParameters.isEmpty
              ? null
              : luckHunterUri.queryParameters,
        );
      }

      return luckHunterUri;
    }

    if (luckHunterScheme == 'tel') {
      return Uri.parse(
          'tel:${_luckHunterDigitsOnly(luckHunterUri.path)}');
    }

    if (luckHunterScheme == 'mailto') {
      return luckHunterUri;
    }

    if (luckHunterScheme == 'bnl') {
      final String luckHunterNewPath =
      luckHunterUri.path.isNotEmpty ? luckHunterUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$luckHunterNewPath',
        luckHunterUri.queryParameters.isEmpty
            ? null
            : luckHunterUri.queryParameters,
      );
    }

    return luckHunterUri;
  }

  Future<bool> _openLuckHunterMailWeb(Uri luckHunterMailto) async {
    final Uri luckHunterGmailUri =
    _luckHunterGmailize(luckHunterMailto);
    return await _openLuckHunterWeb(luckHunterGmailUri);
  }

  Uri _luckHunterGmailize(Uri luckHunterMailUri) {
    final Map<String, String> luckHunterQueryParams =
        luckHunterMailUri.queryParameters;

    final Map<String, String> luckHunterParams =
    <String, String>{
      'view': 'cm',
      'fs': '1',
      if (luckHunterMailUri.path.isNotEmpty)
        'to': luckHunterMailUri.path,
      if ((luckHunterQueryParams['subject'] ?? '').isNotEmpty)
        'su': luckHunterQueryParams['subject']!,
      if ((luckHunterQueryParams['body'] ?? '').isNotEmpty)
        'body': luckHunterQueryParams['body']!,
      if ((luckHunterQueryParams['cc'] ?? '').isNotEmpty)
        'cc': luckHunterQueryParams['cc']!,
      if ((luckHunterQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': luckHunterQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', luckHunterParams);
  }

  Future<bool> _openLuckHunterWeb(Uri luckHunterUri) async {
    try {
      if (await launchUrl(
        luckHunterUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        luckHunterUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (luckHunterError) {
      debugPrint(
          'openInAppBrowser error: $luckHunterError; url=$luckHunterUri');
      try {
        return await launchUrl(
          luckHunterUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _openLuckHunterExternal(Uri luckHunterUri) async {
    try {
      return await launchUrl(
        luckHunterUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (luckHunterError) {
      debugPrint(
          'openExternal error: $luckHunterError; url=$luckHunterUri');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _bindLuckHunterNotificationTap(); // повторная привязка

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            if (luckHunterCoverVisible)
              const LuckHunterLightningLoader()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: <Widget>[
                    InAppWebView(
                      key: ValueKey<int>(luckHunterHatchCounter),
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
                        transparentBackground: true,
                      ),
                      initialUrlRequest: URLRequest(
                        url: WebUri(luckHunterHomeUrl),
                      ),
                      onWebViewCreated:
                          (InAppWebViewController luckHunterController) {
                        luckHunterWebViewController = luckHunterController;

                        luckHunterBosun ??= LuckHunterBosun(
                          luckHunterDeviceDeck: luckHunterDeviceDeck,
                          luckHunterSpy: luckHunterSpy,
                        );

                        luckHunterCourier ??= LuckHunterCourier(
                          luckHunterBosun: luckHunterBosun!,
                          getLuckHunterWebView: () =>
                          luckHunterWebViewController,
                        );

                        luckHunterWebViewController.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (List<dynamic> luckHunterArgs) {
                            try {

                            } catch (_) {}

                            if (luckHunterArgs.isEmpty) {
                              return null;
                            }

                            try {
                              return luckHunterArgs.reduce(
                                      (dynamic current, dynamic next) =>
                                  current + next);
                            } catch (_) {
                              return luckHunterArgs.first;
                            }
                          },
                        );
                      },
                      onLoadStart: (InAppWebViewController luckHunterC,
                          Uri? luckHunterUri) async {
                        setState(() {
                          luckHunterStartLoadTimestamp =
                              DateTime.now()
                                  .millisecondsSinceEpoch;
                        });

                        final Uri? luckHunterViewUri = luckHunterUri;
                        if (luckHunterViewUri != null) {
                          if (_isLuckHunterBareEmail(luckHunterViewUri)) {
                            try {
                              await luckHunterC.stopLoading();
                            } catch (_) {}
                            final Uri luckHunterMailto =
                            _toLuckHunterMailto(luckHunterViewUri);
                            await _openLuckHunterMailWeb(luckHunterMailto);
                            return;
                          }

                          final String luckHunterScheme =
                          luckHunterViewUri.scheme
                              .toLowerCase();
                          if (luckHunterScheme != 'http' &&
                              luckHunterScheme != 'https') {
                            try {
                              await luckHunterC.stopLoading();
                            } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (
                          InAppWebViewController luckHunterController,
                          Uri? luckHunterUrl,
                          int luckHunterCode,
                          String luckHunterMessage,
                          ) async {
                        final int luckHunterNow =
                            DateTime.now().millisecondsSinceEpoch;
                        final String luckHunterEvent =
                            'InAppWebViewError(code=$luckHunterCode, message=$luckHunterMessage)';

                        await luckHunterPostStat(
                          luckHunterEvent: luckHunterEvent,
                          luckHunterTimeStart: luckHunterNow,
                          luckHunterTimeFinish: luckHunterNow,
                          luckHunterUrl:
                          luckHunterUrl?.toString() ?? '',
                          luckHunterAppSid:
                          luckHunterSpy.luckHunterAfUid,
                          luckHunterFirstPageLoadTs:
                          luckHunterFirstPageTimestamp,
                        );
                      },

                      onReceivedError: (
                          InAppWebViewController luckHunterController,
                          WebResourceRequest luckHunterRequest,
                          WebResourceError luckHunterError,
                          ) async {
                        final int luckHunterNow =
                            DateTime.now().millisecondsSinceEpoch;
                        final String luckHunterDescription =
                        (luckHunterError.description ?? '')
                            .toString();
                        final String luckHunterEvent =
                            'WebResourceError(code=${luckHunterError}, message=$luckHunterDescription)';

                        await luckHunterPostStat(
                          luckHunterEvent: luckHunterEvent,
                          luckHunterTimeStart: luckHunterNow,
                          luckHunterTimeFinish: luckHunterNow,
                          luckHunterUrl:
                          luckHunterRequest.url?.toString() ?? '',
                          luckHunterAppSid:
                          luckHunterSpy.luckHunterAfUid,
                          luckHunterFirstPageLoadTs:
                          luckHunterFirstPageTimestamp,
                        );
                      },
                      onLoadStop: (InAppWebViewController luckHunterC,
                          Uri? luckHunterUri) async {
                        await luckHunterC.evaluateJavascript(
                          source:
                          'console.log(\'NeonCinema harbor up!\');',
                        );

                        await _pushLuckHunterDevice();
                        await _pushLuckHunterAfData();

                        setState(() {
                          luckHunterCurrentUrl =
                              luckHunterUri.toString();
                        });

                        Future<void>.delayed(
                            const Duration(seconds: 20), () {
                          sendLuckHunterLoadedOnce(
                            luckHunterUrl:
                            luckHunterCurrentUrl.toString(),
                            luckHunterTimestart:
                            luckHunterStartLoadTimestamp,
                          );
                        });
                      },
                      shouldOverrideUrlLoading: (
                          InAppWebViewController luckHunterC,
                          NavigationAction luckHunterAction,
                          ) async {
                        final Uri? luckHunterUri =
                            luckHunterAction.request.url;
                        if (luckHunterUri == null) {
                          return NavigationActionPolicy.ALLOW;
                        }

                        if (_isLuckHunterBareEmail(luckHunterUri)) {
                          final Uri luckHunterMailto =
                          _toLuckHunterMailto(luckHunterUri);
                          await _openLuckHunterMailWeb(
                              luckHunterMailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final String luckHunterScheme =
                        luckHunterUri.scheme.toLowerCase();

                        if (luckHunterScheme == 'mailto') {
                          await _openLuckHunterMailWeb(luckHunterUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (luckHunterScheme == 'tel') {
                          await launchUrl(
                            luckHunterUri,
                            mode: LaunchMode.externalApplication,
                          );
                          return NavigationActionPolicy.CANCEL;
                        }

                        final String luckHunterHost =
                        luckHunterUri.host.toLowerCase();
                        final bool luckHunterIsSocial =
                            luckHunterHost.endsWith('facebook.com') ||
                                luckHunterHost
                                    .endsWith('instagram.com') ||
                                luckHunterHost.endsWith('twitter.com') ||
                                luckHunterHost.endsWith('x.com');

                        if (luckHunterIsSocial) {
                          await _openLuckHunterExternal(
                              luckHunterUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (_isLuckHunterPlatformish(luckHunterUri)) {
                          final Uri luckHunterWebUri =
                          _luckHunterHttpize(luckHunterUri);
                          await _openLuckHunterExternal(
                              luckHunterWebUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (luckHunterScheme != 'http' &&
                            luckHunterScheme != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (
                          InAppWebViewController luckHunterC,
                          CreateWindowAction luckHunterRequest,
                          ) async {
                        final Uri? luckHunterUri =
                            luckHunterRequest.request.url;
                        if (luckHunterUri == null) {
                          return false;
                        }

                        if (_isLuckHunterBareEmail(luckHunterUri)) {
                          final Uri luckHunterMailto =
                          _toLuckHunterMailto(luckHunterUri);
                          await _openLuckHunterMailWeb(
                              luckHunterMailto);
                          return false;
                        }

                        final String luckHunterScheme =
                        luckHunterUri.scheme.toLowerCase();

                        if (luckHunterScheme == 'mailto') {
                          await _openLuckHunterMailWeb(luckHunterUri);
                          return false;
                        }

                        if (luckHunterScheme == 'tel') {
                          await launchUrl(
                            luckHunterUri,
                            mode: LaunchMode.externalApplication,
                          );
                          return false;
                        }

                        final String luckHunterHost =
                        luckHunterUri.host.toLowerCase();
                        final bool luckHunterIsSocial =
                            luckHunterHost.endsWith('facebook.com') ||
                                luckHunterHost
                                    .endsWith('instagram.com') ||
                                luckHunterHost.endsWith('twitter.com') ||
                                luckHunterHost.endsWith('x.com');

                        if (luckHunterIsSocial) {
                          await _openLuckHunterExternal(
                              luckHunterUri);
                          return false;
                        }

                        if (_isLuckHunterPlatformish(luckHunterUri)) {
                          final Uri luckHunterWebUri =
                          _luckHunterHttpize(luckHunterUri);
                          await _openLuckHunterExternal(
                              luckHunterWebUri);
                          return false;
                        }

                        if (luckHunterScheme == 'http' ||
                            luckHunterScheme == 'https') {
                          luckHunterC.loadUrl(
                            urlRequest:
                            URLRequest(url: WebUri(luckHunterUri.toString())),
                          );
                        }

                        return false;
                      },
                      onDownloadStartRequest:
                          (InAppWebViewController luckHunterC,
                          DownloadStartRequest luckHunterReq) async {
                        await _openLuckHunterExternal(
                            luckHunterReq.url);
                      },
                    ),
                    Visibility(
                      visible: !luckHunterVeilVisible,
                      child: const LuckHunterLightningLoader(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Отдельный WebView для внешней ссылки (из уведомлений)
// ============================================================================

class LuckHunterExternalScreen extends StatefulWidget
    with WidgetsBindingObserver {
  final String luckHunterLane;

  const LuckHunterExternalScreen(this.luckHunterLane, {super.key});

  @override
  State<LuckHunterExternalScreen> createState() =>
      _LuckHunterExternalScreenState();
}

class _LuckHunterExternalScreenState
    extends State<LuckHunterExternalScreen>
    with WidgetsBindingObserver {
  late InAppWebViewController luckHunterExternalWebView;

  @override
  Widget build(BuildContext context) {
    final bool luckHunterIsDark =
        MediaQuery.of(context).platformBrightness ==
            Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
      luckHunterIsDark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: InAppWebView(
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
          initialUrlRequest:
          URLRequest(url: WebUri(widget.luckHunterLane)),
          onWebViewCreated:
              (InAppWebViewController luckHunterC) {
            luckHunterExternalWebView = luckHunterC;
          },
        ),
      ),
    );
  }
}

// ============================================================================
// Help экраны
// ============================================================================

class LuckHunterHelp extends StatefulWidget {
  const LuckHunterHelp({super.key});

  @override
  State<LuckHunterHelp> createState() =>
      _LuckHunterHelpState();
}

class _LuckHunterHelpState extends State<LuckHunterHelp>
    with WidgetsBindingObserver {
  InAppWebViewController? luckHunterHelpController;
  bool luckHunterShowSpinner = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            InAppWebView(
              initialFile: 'assets/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                disableHorizontalScroll: false,
                disableVerticalScroll: false,
              ),
              onWebViewCreated:
                  (InAppWebViewController luckHunterC) {
                luckHunterHelpController = luckHunterC;
              },
              onLoadStart: (InAppWebViewController luckHunterC,
                  Uri? luckHunterUri) {
                setState(() {
                  luckHunterShowSpinner = true;
                });
              },
              onLoadStop: (InAppWebViewController luckHunterC,
                  Uri? luckHunterUri) async {
                setState(() {
                  luckHunterShowSpinner = false;
                });
              },
              onLoadError: (
                  InAppWebViewController luckHunterC,
                  Uri? luckHunterUri,
                  int luckHunterCode,
                  String luckHunterMsg,
                  ) {
                setState(() {
                  luckHunterShowSpinner = false;
                });
              },
            ),
            if (luckHunterShowSpinner)
              const LuckHunterLightningLoader(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(
      luckHunterFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(
        true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LuckHunterHall(),
    ),
  );
}