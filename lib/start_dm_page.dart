// lib/start_dm_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'utils/thread_id.dart';
import 'chat_page.dart';

class StartDmPage extends StatelessWidget {
  final String myUsername;
  const StartDmPage({super.key, required this.myUsername});

  Future<void> _ensureDmDoc(String threadId, String me, String other) async {
    final ref = FirebaseFirestore.instance.collection('dms').doc(threadId);
    await ref.set({
      'members': [me, other],
      'lastMessage': '',
      'lastTime': FieldValue.serverTimestamp(),
      'typing': {},
      'lastRead': {},
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';

    return Scaffold(
      appBar: AppBar(title: const Text('بدء محادثة جديدة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs.where((u) => u.id != myUid).toList();
          if (docs.isEmpty)
            return const Center(child: Text('لا يوجد مستخدمون آخرون.'));

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = docs[i];
              final data = u.data();
              final name = data['username'] ?? 'مستخدم';

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(name),
                subtitle: Text(u.id),
                onTap: () async {
                  final threadId = buildThreadId(myUid, u.id);
                  await _ensureDmDoc(threadId, myUid, u.id);
                  if (!context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        username: myUsername,
                        roomId: threadId,
                        rootCollection: 'dms',
                        roomTitle: name,
                        peerUid: u.id,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
