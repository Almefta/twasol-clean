# twasol-clean

[![CI](https://github.com/Almefta/twasol-clean/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/Almefta/twasol-clean/actions/workflows/flutter-ci.yml)

تطبيق Flutter (دردشة/إشعارات/… حسب وصف مشروعك). هذا المستودع مهيّأ للعمل على فروع `dev` و `main` مع CI.

## Dev notes
- أول تعديل تجريبي على فرع `dev`.
- الفرع الافتراضي للتطوير: `dev`، والدمج يتم عبر Pull Request إلى `main`.

## الميزات (مثال)
- تسجيل الدخول والمستخدمين (feature: `auth`)
- المحادثات (feature: `chat`)
- الإشعارات (FCM)

## المتطلبات
- Flutter SDK (3.x فأعلى)
- Dart SDK مرفق مع Flutter
- Android Studio/Xcode للأجهزة الحقيقية أو المحاكيات

## البدء
```bash
flutter pub get
flutter run