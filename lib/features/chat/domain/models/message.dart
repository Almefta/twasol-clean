import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String roomId;
  final String userId;
  final String username;
  final String text;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.text,
    required this.timestamp,
  });

  factory Message.fromFirestore(String id, String roomId, Map<String, dynamic> data) {
    final ts = data['ts'];
    DateTime when;
    if (ts is Timestamp) {
      when = ts.toDate();
    } else if (ts is DateTime) {
      when = ts;
    } else if (ts is String) {
      when = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      when = DateTime.now();
    }
    return Message(
      id: id,
      roomId: roomId,
      userId: (data['userId'] ?? '') as String,
      username: (data['username'] ?? 'مجهول') as String,
      text: (data['text'] ?? '') as String,
      timestamp: when,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'username': username,
      'text': text,
      'ts': FieldValue.serverTimestamp(),
    };
  }
}
