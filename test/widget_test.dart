import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twasol_clean/main.dart'; // اسم الحزمة الجديد

void main() {
  testWidgets('App builds without crashing', (tester) async {
    await tester.pumpWidget(const MyApp()); // MyApp موجود في main.dart عندك
    await tester.pump(); // يعطي فريم واحد للبناء الأول
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
