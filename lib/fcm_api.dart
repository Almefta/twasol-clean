import 'package:firebase_messaging/firebase_messaging.dart';

class FCMApi {
  static final _firebaseMessaging = FirebaseMessaging.instance;

  static Future<void> initNotifications() async {
    await _firebaseMessaging.requestPermission();
    // Handle foreground messages, background messages, etc.
    // For example:
    // FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    //   print('Got a message whilst in the foreground!');
    //   print('Message data: ${message.data}');
    //
    //   if (message.notification != null) {
    //     print('Message also contained a notification: ${message.notification}');
    //   }
    // });
  }

  static Future<String?> getFCMToken() async {
    return await _firebaseMessaging.getToken();
  }
}
