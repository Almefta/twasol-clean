// lib/home_page.dart
// شاشة البداية: تبويبات (خاص، مجموعات، جهات الاتصال) + حالة التواجد (online)
// + زر ينسخ UID الحالي إلى الحافظة لبدء دردشة خاصة مؤقتًا بالـ UID إن لزم.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'dms_list_page.dart'; // تبويب الدردشات الخاصة
import 'rooms_page.dart'; // تبويب المجموعات
import 'contacts_page.dart'; // ✅ تبويب جهات الاتصال

class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final String _uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    _ensureUserDoc();
    _setPresence(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setPresence(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setPresence(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _setPresence(false);
    }
  }

  Future<void> _ensureUserDoc() async {
    if (_uid == 'anon') return;
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'username': widget.username,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setPresence(bool online) async {
    if (_uid == 'anon') return;
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'isOnline': online,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _copyMyUid() async {
    await Clipboard.setData(ClipboardData(text: _uid));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('نُسخ UID: $_uid')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // خاص + مجموعات + جهات الاتصال
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Twasol'),
          actions: [
            IconButton(
              tooltip: 'نسخ معرفي (UID)',
              icon: const Icon(Icons.copy),
              onPressed: _copyMyUid,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'خاص'),
              Tab(text: 'مجموعات'),
              Tab(text: 'جهات الاتصال'),
            ],
          ),
        ),
        // ⚠️ مهم: نفس ترتيب التبويبات تمامًا
        body: TabBarView(
          children: [
            DmsListPage(username: widget.username), // 1) خاص
            RoomsPage(username: widget.username), // 2) مجموعات
            const ContactsPage(), // 3) جهات الاتصال ✅
          ],
        ),
      ),
    );
  }
}
