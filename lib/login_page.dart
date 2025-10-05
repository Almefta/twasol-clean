// lib/login_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  final void Function(String username) onLogin;
  const LoginPage({super.key, required this.onLogin});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _c = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final name = (v ?? '').trim();
    if (name.isEmpty) return 'الاسم مطلوب';
    if (name.length < 2) return 'الاسم قصير جدًا';
    if (name.length > 24) return 'الاسم طويل جدًا (الحد 24)';
    // رموز مزعجة لاسم المستخدم (اسم العرض)
    final bad = RegExp(r'[\/#\[\]\?<>]'); // لا نسمح بها
    if (bad.hasMatch(name)) return 'الاسم يحتوي رموزًا غير مسموح بها';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final username = _c.text.trim();

    setState(() => _loading = true);
    try {
      // تأكد أن لدينا مستخدم مصادق (مجهول إن لزم)
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      final uid = auth.currentUser!.uid;

      final users = FirebaseFirestore.instance.collection('users');

      // 1) منع تكرار الاسم لمستخدم آخر
      final dup =
          await users.where('username', isEqualTo: username).limit(1).get();
      if (dup.docs.isNotEmpty && dup.docs.first.id != uid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الاسم مستخدم بالفعل، جرّب اسمًا آخر')),
        );
        return;
      }

      // 2) إنشاء/تحديث وثيقة المستخدم
      final userRef = users.doc(uid);
      final exists = (await userRef.get()).exists;

      final data = <String, dynamic>{
        'username': username,
        'lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!exists) {
        data['createdAt'] = FieldValue.serverTimestamp();
      }

      await userRef.set(data, SetOptions(merge: true));

      // 3) الرجوع للتطبيق
      if (mounted) widget.onLogin(username);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تسجيل الدخول: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل الاسم')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _c,
                  decoration: const InputDecoration(
                    labelText: 'اكتب اسمك',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  validator: _validate,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(_loading ? 'جاري الدخول...' : 'دخــــول'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
