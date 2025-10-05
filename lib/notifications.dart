// ملف: lib/notifications.dart
//
// مسؤول عن:
// - تهيئة قنوات الإشعارات (Android)
// - إظهار إشعار محلي عند استقبال رسالة FCM في المقدمة
// - التوجيه إلى صفحة الدردشة عند الضغط على الإشعار (foreground/background/terminated)
// - معالج الخلفية لرسائل FCM
//
// ملاحظات:
// - صلاحية POST_NOTIFICATIONS على أندرويد 13+ تُطلب في FcmTokens (ملف notifications_tokens.dart)
// - لا نستعمل AndroidFlutterLocalNotificationsPlugin.requestPermission() (غير متوفر على أندرويد)
// - للتوجيه نستخدم navigatorKey الذي يتم تمريره من main.dart عبر setNavigatorKey()

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

// مفتاح الملاحة العام نمرره من main.dart
GlobalKey<NavigatorState>? _navKey;

// ملحق الإشعارات المحلية
final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

// قناة أندرويد (يجب أن تكون ثابتة وتُنشأ مرة واحدة)
const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'chat_messages_channel', // ID ثابت — يجب أن يطابقه السيرفر في channel_id
  'Chat Messages', // Name
  description: 'Notifications for chat messages',
  importance: Importance.high,
  playSound: true,
  showBadge: true,
);

/// مُعرّف القناة للاستخدام الخارجي (مثلاً: في الخادم عند الإرسال)
/// ملاحظة: يجب تمرير نفس القيمة في "android.notification.channel_id" في طلب FCM.
String get channelId => _androidChannel.id;

// دالة خلفية رسائل FCM (لا تلمس التوجيه هنا؛ فقط ممكن تسجّل لوج)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // لازم تهيئة Firebase في isolate الخلفي
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // يمكن لاحقًا إضافة منطق خفيف إن لزم (مثلاً تسجيل Telemetry)
  // ملاحظة: لا تنفّذ Navigation هنا.
}

class AppNotifications {
  AppNotifications._();

  /// يمرّر navigatorKey القادم من main.dart لتمكين التوجيه بالضغط على الإشعار
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navKey = key;
  }

  /// تهيئة الإشعارات + مستمعي FCM + القناة المحلية
  static Future<void> init() async {
    // سجّل معالج الخلفية قبل أي شيء
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // تهيئة flutter_local_notifications
    // ✅ نحدد أيقونة صغيرة مخصّصة للإشعارات (أبيض/شفاف) — أنشئ @drawable/ic_stat_notify
    //   راجع الشرح: ضع ic_stat_notify.xml (Vector) في android/app/src/main/res/drawable/
    const androidInit =
        AndroidInitializationSettings('@drawable/ic_stat_notify');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    // onDidReceiveNotificationResponse: الضغط على الإشعار (foreground/background)
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final map = jsonDecode(payload) as Map<String, dynamic>;
          _navigateFromPayload(map);
        } catch (_) {
          // تجاهل أي JSON غير صالح في الـ payload
        }
      },
    );

    // إنشاء قناة أندرويد (مرّة واحدة)
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);

    // التطبيق في المقدمة: أظهر إشعارًا محليًا + بانر داخل التطبيق
    FirebaseMessaging.onMessage.listen((msg) async {
      // ✅ نأخذ العنوان من notification أو من data (لدعم data-only)
      final notifTitle = msg.notification?.title ?? msg.data['title'];
      debugPrint(
        'FCM onMessage title: ' +
            ((notifTitle == null || notifTitle.isEmpty)
                ? '(no title)'
                : notifTitle),
      );

      // إشعار محلي سريع (Foreground)
      await _showLocalForRemote(msg);

      // بانر داخل التطبيق مع زر فتح (اختياري)
      final ctx = _navKey?.currentContext;
      if (ctx != null) {
        final notification = msg.notification;
        final data = msg.data;

        // ✅ fallback ذكي للعنوان/النص
        final title = (notification?.title?.trim().isNotEmpty == true)
            ? notification!.title!
            : (data['title'] ?? 'رسالة جديدة');
        final body = (notification?.body?.trim().isNotEmpty == true)
            ? notification!.body!
            : (data['body'] ?? '');

        final payload = _buildPayloadFromRemote(msg);
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('$title: ${body.isEmpty ? '...' : body}'),
            action: SnackBarAction(
              label: 'فتح',
              onPressed: () {
                _navigateFromPayload(payload);
              },
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    // فتح من الإشعار والتطبيق في الخلفية:
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final notifTitle = msg.notification?.title ?? msg.data['title'];
      debugPrint(
        'FCM onMessageOpenedApp title: ' +
            ((notifTitle == null || notifTitle.isEmpty)
                ? '(no title)'
                : notifTitle),
      );
      final payload = _buildPayloadFromRemote(msg);
      _navigateFromPayload(payload);
    });
  }

  /// للتحقق عند بدء التشغيل: إذا فُتح التطبيق من إشعار وهو مغلق (terminated)
  static Future<void> checkInitialMessage() async {
    final msg = await FirebaseMessaging.instance.getInitialMessage();
    if (msg == null) return;
    final payload = _buildPayloadFromRemote(msg);
    _navigateFromPayload(payload);
  }

  /// يبني حمولة التوجيه من RemoteMessage (data/notification)
  /// نتوقع من السحابة (أو من console) أن ترسل:
  /// route=/chat, roomId=..., root=rooms|dms, title=..., peerUid=...
  static Map<String, dynamic> _buildPayloadFromRemote(RemoteMessage msg) {
    final data = msg.data;

    final route = data['route'] ?? '/chat';
    final roomId = data['roomId'];
    final root = data['root'] ?? 'rooms';
    final title = data['title'] ?? msg.notification?.title;
    final peerUid = data['peerUid'];

    return {
      'route': route,
      'roomId': roomId,
      'root': root,
      'title': title,
      'peerUid': peerUid,
    };
  }

  /// إظهار إشعار محلي للرسالة الواردة في المقدمة (وأيضًا data-only)
  static Future<void> _showLocalForRemote(RemoteMessage msg) async {
    if (kIsWeb) return; // الويب يُدار عبر SW

    final notification = msg.notification;
    final android = notification?.android;

    final payload = jsonEncode(_buildPayloadFromRemote(msg));

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        priority: Priority.high,
        importance: Importance.high,
        playSound: true,
        // ✅ نستخدم أيقونتنا البيضاء المخصّصة؛ وإن جاء smallIcon من FCM نُبقيه
        icon: android?.smallIcon ?? '@drawable/ic_stat_notify',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    // ✅ تحضير عنوان/نص حتى في حالة data-only
    final title = (notification?.title?.trim().isNotEmpty == true)
        ? notification!.title!
        : (msg.data['title'] ?? 'رسالة جديدة');
    final body = (notification?.body?.trim().isNotEmpty == true)
        ? notification!.body!
        : (msg.data['body'] ?? 'لديك رسالة جديدة');

    await _local.show(
      msg.hashCode, // معرّف فريد للإشعار
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// تنفيذ التوجيه بناءً على الحمولة
  static void _navigateFromPayload(Map<String, dynamic> payload) {
    final nav = _navKey?.currentState;
    if (nav == null) return;

    final route = payload['route'] as String? ?? '/chat';
    if (route != '/chat') return;

    final roomId = payload['roomId'] as String?;
    if (roomId == null || roomId.isEmpty) return;

    final root = (payload['root'] as String?) ?? 'rooms';
    final title = payload['title'] as String?;
    final peerUid = payload['peerUid'] as String?;

    nav.pushNamed(
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
