// lib/rooms_page.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'chat_page.dart';

class RoomsPage extends StatelessWidget {
  final String username;
  const RoomsPage({super.key, required this.username});

  Future<void> _createRoom(BuildContext context) async {
    final c = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إنشاء مجموعة جديدة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: c,
                  decoration: const InputDecoration(
                    hintText: 'اسم المجموعة (مثال: general)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = c.text.trim();
                  final invalid = RegExp(
                    r'[\/\?\#\[\]]',
                  ); // رموز غير مسموحة في docId
                  if (name.isEmpty) {
                    setState(() => error = 'الاسم مطلوب');
                    return;
                  }
                  if (invalid.hasMatch(name)) {
                    setState(() => error = 'الاسم يحتوي رموزًا غير مسموح بها');
                    return;
                  }

                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('لم يتم تسجيل الدخول')),
                      );
                    }
                    return;
                  }

                  // نستخدم اسم الغرفة كـ docId مثل السابق
                  final ref = FirebaseFirestore.instance
                      .collection('rooms')
                      .doc(name);

                  await ref.set({
                    'name': name,
                    'createdAt': FieldValue.serverTimestamp(),
                    'lastMessage': '',
                    'lastSender': '',
                    'lastTime': FieldValue.serverTimestamp(),
                    // مهم جداً حتى تسمح القواعد بالقراءة/الكتابة
                    'members': [uid],
                    'admins': [uid],
                  }, SetOptions(merge: true));

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('إنشاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(Timestamp? ts) =>
      ts == null ? '' : DateFormat('hh:mm a').format(ts.toDate());

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // 👇 الاستعلام الآن يتحقق من العضوية ليتوافق مع القواعد
    final roomsQuery = FirebaseFirestore.instance
        .collection('rooms')
        .where('members', arrayContains: uid)
        .orderBy('lastTime', descending: true);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المجموعات'),
          actions: [
            IconButton(
              tooltip: 'إنشاء مجموعة',
              icon: const Icon(Icons.add),
              onPressed: () => _createRoom(context),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _createRoom(context),
          child: const Icon(Icons.add),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: roomsQuery.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              // لو ظهرت failed-precondition مع رابط، افتح الرابط لإنشاء الفهرس
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('خطأ أثناء جلب المجموعات:\n${snap.error}'),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Center(
                child: Text('لا توجد مجموعات بعد. اضغط + لإنشاء مجموعة.'),
              );
            }

            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = docs[i];
                final m = d.data();

                final roomName = (m['name'] as String?)?.trim();
                final lastMsg = (m['lastMessage'] as String?)?.trim() ?? '';
                final lastSender = (m['lastSender'] as String?)?.trim() ?? '';
                final lastTime = _fmt(m['lastTime'] as Timestamp?);

                final titleText = (roomName == null || roomName.isEmpty)
                    ? d.id
                    : roomName;

                final subtitle = lastMsg.isEmpty
                    ? 'لا توجد رسائل'
                    : (lastSender.isEmpty ? lastMsg : '$lastSender: $lastMsg');

                return ListTile(
                  title: Text(
                    titleText,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    subtitle,
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
                          username: username,
                          roomId: d.id,
                          rootCollection: 'rooms', // القراءة/الكتابة من rooms
                          roomTitle: titleText,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
