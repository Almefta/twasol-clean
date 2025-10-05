// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ✅ عدّل اسم الباكدج هنا ليطابق name في pubspec.yaml
import 'package:twasol_ai/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(); // أول فريم بعد initState

    // نتأكد أن MaterialApp موجود (تطبيقك يشتغل)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
