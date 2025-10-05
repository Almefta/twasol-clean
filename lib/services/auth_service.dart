import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> saveUserToken(String userId) async {
    // جلب التوكن الحالي
    String? token = await _fcm.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection("users").doc(userId).update({
        "fcmToken": token,
      });
      print("✅ FCM Token تم حفظه: $token");
    }

    // تحديث التوكن لو تغيّر
    _fcm.onTokenRefresh.listen((newToken) async {
      await FirebaseFirestore.instance.collection("users").doc(userId).update({
        "fcmToken": newToken,
      });
      print("🔄 Token محدث: $newToken");
    });
  }
}
