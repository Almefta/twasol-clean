import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'chat_page.dart';

/// نولّد معرف محادثة ثابت لأي ثنائي (A,B)
String dmRoomId(String a, String b) {
  final x = a.compareTo(b) <= 0 ? a : b;
  final y = a.compareTo(b) <= 0 ? b : a;
  return 'dm_${x}_$y';
}

class UsersPage extends StatelessWidget {
  final String currentUid;
  final String currentUsername;
  const UsersPage({
    super.key,
    required this.currentUid,
    required this.currentUsername,
  });

  @override
  Widget build(BuildContext context) {
    final usersRef =
        FirebaseFirestore.instance.collection('users').orderBy('username');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<QuerySnapshot>(
        stream: usersRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());

          final docs =
              snap.data!.docs.where((d) => d.id != currentUid).toList();
          if (docs.isEmpty)
            return const Center(child: Text('لا يوجد مستخدمون آخرون بعد.'));

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>? ?? {};
              final otherUid = docs[i].id;
              final otherName = (data['username'] as String?) ?? 'مستخدم';

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(otherName),
                subtitle: const Text('بدء محادثة خاصة'),
                onTap: () async {
                  final roomId = dmRoomId(currentUid, otherUid);

                  // أنشئ/حدّث وثيقة الـ DM
                  await FirebaseFirestore.instance
                      .collection('dms')
                      .doc(roomId)
                      .set({
                    'members': [currentUid, otherUid],
                    'memberUsernames': {
                      currentUid: currentUsername,
                      otherUid: otherName,
                    },
                    'createdAt': FieldValue.serverTimestamp(),
                    'lastMessage': null,
                    'lastTime': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));

                  if (context.mounted) {
                    // بعد إنشاء/الحصول على roomId
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          username: currentUsername,
                          roomId: roomId,
                          rootCollection: 'dms',
                          roomTitle: otherName,
                          peerUid: otherUid, // 👈 مهم
                        ),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
