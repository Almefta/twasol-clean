// lib/dms_list_page.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'chat_page.dart';

class DmsListPage extends StatelessWidget {
  final String username; // اسم المستخدم الحالي (لعرضه/تمريره لصفحة المحادثة)
  const DmsListPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final String myUid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';

    // نعرض كل محادثات الخاص التي "أنا" عضو فيها، مرتبة بآخر وقت
    final query = FirebaseFirestore.instance
        .collection('dms')
        .where('members', arrayContains: myUid)
        .orderBy('lastTime', descending: true);

    String fmt(Timestamp? ts) =>
        ts == null ? '' : DateFormat('hh:mm a').format(ts.toDate());

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('خطأ أثناء جلب الدردشات الخاصة:\n${snap.error}'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('لا توجد دردشات خاصة'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final m = d.data();

              // الأعضاء في هذه المحادثة
              final List members = (m['members'] as List?) ?? const [];
              // الطرف الآخر (غير أنا)
              final String peerUid = members
                      .firstWhere(
                        (x) => x != myUid,
                        orElse: () => myUid,
                      )
                      .toString();

              final String lastMsg = (m['lastMessage'] as String?)?.trim() ?? '';
              final String lastTime = fmt(m['lastTime'] as Timestamp?);

              // نقرأ اسم الطرف الآخر من users/{peerUid}
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(peerUid)
                    .snapshots(),
                builder: (context, uSnap) {
                  String title = peerUid; // افتراضيًا المعرّف
                  if (uSnap.hasData && uSnap.data?.data() != null) {
                    final data = uSnap.data!.data()!;
                    final name = (data['username'] as String?)?.trim() ?? '';
                    if (name.isNotEmpty) title = name;
                  } else {
                    // إن لم نجد وثيقة المستخدم، نحاول الاستفادة من حقل اختياري قد يكون موجوداً داخل محادثة DM
                    final Map<String, dynamic>? tByUid =
                        (m['titleByUid'] as Map?)?.cast<String, dynamic>();
                    if (tByUid != null && tByUid[peerUid] is String) {
                      final n = (tByUid[peerUid] as String).trim();
                      if (n.isNotEmpty) title = n;
                    }
                  }

                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      lastMsg.isEmpty ? 'لا توجد رسائل' : lastMsg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      lastTime,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(
                            username: username, // اسمي أنا
                            roomId: d.id, // threadId
                            rootCollection: 'dms',
                            roomTitle: title, // اسم الطرف الآخر لعنوان الصفحة
                            peerUid: peerUid,  // مهم لحالة "يكتب الآن" والحضور
                          ),
                        ),
                      );
                    },
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
