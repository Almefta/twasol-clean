// lib/utils/thread_id.dart
String buildThreadId(String a, String b) {
  final list = [a, b]..sort();
  return '${list[0]}_${list[1]}';
}
