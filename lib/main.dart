// ملف: lib/main.dart
// الهدف:
// - حل التحذيرات الزرقاء (lint) بدون تغيير منطق التطبيق
// - تهيئة Firebase/FCM بالترتيب الصحيح
// - تمرير navigatorKey للتوجيه من الضغط على الإشعار
// - الحفاظ على شغلك كما هو (Login/Home/Chat/FcmBootstrap)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'notifications.dart'; // نظام الإشعارات المحلي + القناة + التوجيه
import 'notifications_tokens.dart'; // حفظ/تحديث توكن الجهاز في Firestore
import 'chat_page.dart';

// مفتاح ملاحة عام لاستخدامه في التوجيه من الإشعار
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// معالج رسائل FCM في الخلفية (عندما التطبيق بالخلفية/مغلَق)
// ✅ استبدال print بـ debugPrint (تفادي تحذير avoid_print)
// ✅ تهيئة Firebase بخيارات المشروع داخل isolate الخلفي
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // قد تكون مهيّأة مسبقًا
  }
  debugPrint("🔔 رسالة في الخلفية: ${message.messageId}"); // ← كان print
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) تهيئة Firebase قبل أي استخدام
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2) ✅ تفعيل Auto-Init لتفادي حالات token=null المبكرة
  await FirebaseMessaging.instance.setAutoInitEnabled(true);

  // 3) تسجيل معالج الخلفية
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 4) تمرير navigatorKey لنظام الإشعارات
  AppNotifications.setNavigatorKey(navigatorKey);

  // 5) تهيئة نظام الإشعارات المحلي + القناة + مستمعي onMessage/onMessageOpenedApp
  await AppNotifications.init();

  // 6) جلسة دخول (كما في كودك الأصلي)
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  // 7) تشغيل التطبيق
  runApp(const MyApp());

  // 8) بعد التشغيل: طلب الإذن (Android 13+/iOS) + حفظ/تحديث التوكن في Firestore
  unawaited(FcmTokens.initAndSaveForCurrentUser());

  // 9) مستمع طباعة/سناك بار (يبقى كما هو—مع تحسينات الربط النصي)
  FirebaseMessaging.onMessage.listen((message) {
    if (FcmBootstrap.isInitialized) {
      // لتجنّب الازدواج مع مستمعات FcmBootstrap
      return;
    }
    final title = message.notification?.title ?? message.data['title'] ?? '';
    // ✅ استبدال + بـ Interpolation
    debugPrint('FCM onMessage title: ${title.isEmpty ? '(no title)' : title}');
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      final notifTitle = message.notification?.title ?? '(no title)';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(notifTitle)),
      );
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    if (FcmBootstrap.isInitialized) {
      return;
    }
    final title = message.notification?.title ?? message.data['title'] ?? '';
    // ✅ استبدال + بـ Interpolation
    debugPrint(
        'FCM onMessageOpenedApp title: ${title.isEmpty ? '(no title)' : title}');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? username;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    // بعد الإطار الأول: فعّل Bootstrap الخاص بك (يسجل مستمعين مفيدين)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FcmBootstrap.ensureInitialized(context);
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username');
    if (mounted) setState(() => _loadingPrefs = false);

    // بعد أول إطار: تحقق إذا فُتح التطبيق من إشعار وهو مغلق (terminated)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNotifications.checkInitialMessage(); // Android/iOS
      if (kIsWeb) _handleWebDeeplink(); // Web (query params)
    });
  }

  void _handleWebDeeplink() {
    final uri = Uri.base;
    final route = uri.queryParameters['route'];
    final roomId = uri.queryParameters['roomId'];
    if (route == '/chat' && roomId != null && roomId.isNotEmpty) {
      final root = uri.queryParameters['root'] ?? 'rooms';
      final title = uri.queryParameters['title'];
      final peerUid = uri.queryParameters['peerUid'];
      navigatorKey.currentState?.pushNamed(
        '/chat',
        arguments: {
          'roomId': roomId,
          'root': root,
          'title': title,
          'peerUid': peerUid,
        },
      );
    }
  }

  Future<void> _onLogin(String user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', user);
    setState(() => username = user);

    // بعد تسجيل الدخول: تأكد من حفظ توكن الجهاز لهذا المستخدم
    unawaited(FcmTokens.initAndSaveForCurrentUser());
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // ← مهم للتوجيه من الإشعار
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = (settings.arguments as Map?) ?? {};
          final roomId = args['roomId'] as String?;
          final root = (args['root'] as String?) ?? 'rooms';
          final title = args['title'] as String?;
          final peerUid = args['peerUid'] as String?;

          if (roomId != null) {
            return MaterialPageRoute(
              builder: (_) => ChatPage(
                username: username ?? '',
                roomId: roomId,
                rootCollection: root,
                roomTitle: title,
                peerUid: peerUid,
              ),
            );
          }
        }
        return null;
      },
      home: username == null
          ? LoginPage(onLogin: _onLogin)
          : HomePage(username: username!),
    );
  }
}

class FcmBootstrap {
  static bool _inited = false;

  static bool get isInitialized => _inited;

  // ملاحظة: أبقينا توقيع الدالة كما هو (context قادم من MyApp)
  // لكن سنستعيض داخليًّا عن استخدامه بـ navigatorKey.currentContext
  static Future<void> ensureInitialized(BuildContext context) async {
    if (_inited) return;
    _inited = true;

    // جلب التوكن مع حراسة للأخطاء (مفيد للـ debug)
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint("🔑 FCM TOKEN: $token"); // ← كان print
    } catch (e, st) {
      debugPrint('[FCM][ERR][token] $e$st');
    }

    // رسائل foreground: اظهار سناك بار خفيفة بالإضافة إلى إشعار محلي من notifications.dart
    FirebaseMessaging.onMessage.listen((message) {
      try {
        debugPrint(
            '[FCM][FG] title=${message.notification?.title} data=${message.data}');
        // ✅ بدل استخدام context بعد عمليات async، نعتمد على navigatorKey.currentContext
        final messenger =
            ScaffoldMessenger.maybeOf(navigatorKey.currentContext!);
        if (messenger != null) {
          final title = message.notification?.title ?? 'إشعار جديد';
          final body = message.notification?.body ?? '';
          messenger.showSnackBar(
            SnackBar(content: Text(body.isNotEmpty ? '$title – $body' : title)),
          );
        }
      } catch (e, st) {
        debugPrint('[FCM][ERR][onMessage] $e$st');
      }
    });

    // فتح التطبيق من الإشعار (وهو بالخلفية)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      try {
        debugPrint('[FCM][OPEN] data=${message.data}');
        // TODO: يمكنك هنا إضافة تنقّل مخصص إن لم يكن notifications.dart يقوم به
      } catch (e, st) {
        debugPrint('[FCM][ERR][onMessageOpenedApp] $e$st');
      }
    });

    // إشعار وصل والتطبيق مغلق قبل الإقلاع (terminated)
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        debugPrint('[FCM][INITIAL] data=${initial.data}');
        // TODO: تعامل مع الفتح الأولي إذا أردت (أو اتركه لـ AppNotifications.checkInitialMessage)
      }
    } catch (e, st) {
      debugPrint('[FCM][ERR][initial] $e$st');
    }
  }
}
