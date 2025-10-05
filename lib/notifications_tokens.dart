// ملف: lib/notifications_tokens.dart
//
// مسؤول عن:
// - طلب الأذونات اللازمة للإشعارات (iOS + Android 13)
// - جلب/حفظ توكن FCM تحت user_tokens/{uid}/tokens/{token}  ← مسار موحّد للخادم
// - متابعة onTokenRefresh وتحديث السحابة تلقائيًا
//
// ملاحظات:
// - على أندرويد 13+ نستخدم permission_handler (POST_NOTIFICATIONS)
// - على iOS نستخدم FirebaseMessaging.requestPermission
// - يُستحسن مناداة initAndSaveForCurrentUser() بعد تسجيل الدخول مباشرة

import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

class FcmTokens {
  FcmTokens._();

  // 👇 مسار موحّد للتوكنات ليسهل على السيرفر/الفنكشن الوصول لها
  // شكل الوثائق: user_tokens/{uid}/tokens/{token}
  static const String _root = 'user_tokens';

  /// اطلب الأذونات (حسب المنصة) ثم خزّن التوكن للحساب الحالي
  static Future<void> initAndSaveForCurrentUser() async {
    // 0) فعّل auto init لتفادي عدم إنشاء التوكن في أول تشغيل
    await FirebaseMessaging.instance.setAutoInitEnabled(true);

    // 1) أذونات
    await _ensureNotificationPermission();

    // 2) الحصول على التوكن (مع محاولة إعادة بسيطة إن رجع null)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    String? token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      // محاولة ثانية بعد مهلة قصيرة (بعض الأجهزة تتأخر بإعطاء التوكن)
      await Future<void>.delayed(const Duration(seconds: 1));
      token = await FirebaseMessaging.instance.getToken();
    }

    if (token != null && token.isNotEmpty) {
      await _saveToken(uid, token, isNew: true);
    }

    // 3) مستمع تحديث التوكن
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      final u = FirebaseAuth.instance.currentUser?.uid;
      if (u == null || u.isEmpty) return;
      await _saveToken(u, newToken, isNew: true);
    });
  }

  /// طلب أذونات الإشعار
  static Future<void> _ensureNotificationPermission() async {
    if (kIsWeb) {
      // على الويب تُدار عبر المتصفح/SW
      return;
    }

    if (Platform.isIOS) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      return;
    }

    // أندرويد 13+ يحتاج POST_NOTIFICATIONS
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;

      if (status.isGranted) return;

      if (status.isDenied || status.isRestricted || status.isLimited) {
        final r = await Permission.notification.request();
        // لو المستخدم رفض نهائيًا، الأفضل تقترح عليه فتح الإعدادات
        if (r.isPermanentlyDenied) {
          // يمكنك عرض بانر/حوار في طبقة أعلى تدعو لفتح الإعدادات
          // await openAppSettings();
        }
      } else if (status.isPermanentlyDenied) {
        // بإمكانك إظهار بانر خارجي يدعو لفتح الإعدادات
        // await openAppSettings();
      }
    }
  }

  /// حفظ التوكن تحت user_tokens/{uid}/tokens/{token} كوثيقة ID=token
  static Future<void> _saveToken(String uid, String token,
      {bool isNew = false}) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection(_root)
          .doc(uid)
          .collection('tokens')
          .doc(token);

      final data = <String, dynamic>{
        'platform': kIsWeb
            ? 'web'
            : (Platform.isAndroid
                ? 'android'
                : (Platform.isIOS ? 'ios' : 'other')),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isNew) {
        data['createdAt'] = FieldValue.serverTimestamp();
      }

      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// اختياري: نداء عند تسجيل الخروج لإزالة التوكن الحالي
  static Future<void> unregisterCurrentToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await FirebaseFirestore.instance
          .collection(_root)
          .doc(user.uid)
          .collection('tokens')
          .doc(token)
          .delete();
    } catch (e) {
      debugPrint('Error unregistering FCM token: $e');
    }
  }
}
