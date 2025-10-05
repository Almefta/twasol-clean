// lib/user_phone_page.dart
//
// شاشة إدخال/تحديث رقم الهاتف الخاص بي وربطه بفهرس users_by_phone.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserPhonePage extends StatefulWidget {
  const UserPhonePage({super.key});

  @override
  State<UserPhonePage> createState() => _UserPhonePageState();
}

class _UserPhonePageState extends State<UserPhonePage> {
  final c = TextEditingController();
  bool _saving = false;
  String? _err;

  User get _me => FirebaseAuth.instance.currentUser!;

  // مسموح فقط + والأرقام
  String _normalizePhone(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _save() async {
    final raw = c.text.trim();
    final phone = _normalizePhone(raw);

    if (phone.isEmpty || !phone.startsWith('+') || phone.length < 8) {
      setState(() => _err = 'اكتب رقمك بصيغة دولية مثل: +9665xxxxxx');
      return;
    }

    setState(() {
      _saving = true;
      _err = null;
    });

    try {
      // احفظ داخل users/{uid}
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(_me.uid);
      await userRef.set({
        'phoneE164': phone,
      }, SetOptions(merge: true));

      // واجلب الاسم لعرضه للآخرين
      final uSnap = await userRef.get();
      final uname =
          (uSnap.data() ?? const {})['username'] as String? ?? 'مستخدم';

      // ثم أنشئ/حدّث الفهرس users_by_phone/{phone}
      await FirebaseFirestore.instance
          .collection('users_by_phone')
          .doc(phone)
          .set({
        'uid': _me.uid,
        'username': uname,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ رقم الهاتف بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _err = 'فشل الحفظ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('رقم هاتفي')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'اكتب رقمك بصيغة دولية (E.164) مثل: +9665xxxxxx.\n'
                'هذا يسمح لأصدقائك بإيجادك تلقائيًا من جهات الاتصال.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم الهاتف',
                  hintText: '+9665xxxxxx',
                  border: const OutlineInputBorder(),
                  errorText: _err,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'جاري الحفظ…' : 'حفظ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
