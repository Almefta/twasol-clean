// lib/contacts_page.dart
// شاشة جهات الاتصال — نسخة مُحسّنة مع:
// 1) عرض فوري من الكاش ثم تحديث صامت من الجهاز.
// 2) عدم الكتابة فوق الكاش إلا عند نجاح القراءة (تجنّب فقدان الأسماء).
// 3) مطابقة أرقام الهاتف مع users_by_phone بدُفعات (10-10).
// 4) جلب أسماء أصحاب الـ UIDs من users/* بدُفعات (10-10).
// 5) ترتيب “المشتركين” أعلى القائمة + إظهار شارة "مشترك" لهم فقط.
// 6) زر دردشة يعمل فقط للمشتركين، يفتح/ينشئ DM بالـ UID (ثابت حتى لو تغيّر الاسم).
//
// ملاحظات على أخطاء سابقة تم تجنّبها:
// - لا نستخدم ?? '' حين يكون النوع غير قابل للـ null (تفادي dead_null_aware_expression).
// - لا نكتب الكاش بقيمة فارغة عند فشل القراءة.
// - لا نظهر زر دردشة لغير المشتركين.
// - إن كانت الصلاحية مرفوضة، نُبقي الكاش الظاهر ونُظهر بانر لفتح الإعدادات.
//
// يتطلب:
//   permission_handler ^11.x
//   flutter_contacts ^1.1.x
//   cloud_firestore, firebase_auth, shared_preferences

import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _searchCtrl = TextEditingController();

  // الحالة الظاهرة
  final List<_UiContact> _contacts = [];

  // إشارات حالة
  bool _loading = false;
  bool _permPermanentlyDenied = false;

  // رقم المستخدم (E.164) المخزّن محليًا
  String? _myPhone;

  // تذكّر آخر مزامنة ناجحة (اختياري لعرضها)
  DateTime? _lastSuccessfulSync;

  // بلد افتراضي لِتطبيع الأرقام (عدّل حسب حاجتك)
  static const String _defaultCountryCode = '+967';

  @override
  void initState() {
    super.initState();
    _restoreCacheThenRefresh();
  }

  // ---------------- محوِّلات صغيرة آمنة ----------------
  String _orEmpty(String? s) => s == null ? '' : s;
  String _visibleName(String? s) {
    final v = _orEmpty(s).trim();
    return v.isEmpty ? '(بدون اسم)' : v;
  }

  // ---------------- تخزين محلي (SharedPreferences) ----------------
  Future<void> _restoreCacheThenRefresh() async {
    setState(() => _loading = true);

    // 1) حمّل رقمك والكاش واعرضهما فورًا
    await _loadMyPhoneFromPrefs();
    final cached = await _loadContactsCache();
    if (cached.isNotEmpty) {
      setState(() {
        _contacts
          ..clear()
          ..addAll(_sortWithSubscribersFirst(cached));
        _loading = false; // لدينا بيانات نعرضها الآن
      });
    }

    // 2) حدث من الجهاز بشكل صامت (ولا تكتب فوق الكاش إن فشل)
    _refreshFromDeviceAndSaveCache();
  }

  Future<void> _loadMyPhoneFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    _myPhone = p.getString('my_phone_e164');
  }

  Future<void> _saveMyPhoneToPrefs(String phone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('my_phone_e164', phone);
    setState(() => _myPhone = phone);
  }

  Future<List<_UiContact>> _loadContactsCache() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('contacts_cache');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['schema'] != 1) return []; // تجاهل مخطط قديم
      final list = (decoded['items'] as List<dynamic>)
          .map((m) => _UiContact.fromJson(m as Map<String, dynamic>))
          .toList();
      final ts = decoded['lastSync'] as String?;
      if (ts != null) _lastSuccessfulSync = DateTime.tryParse(ts);
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveContactsCache(List<_UiContact> list) async {
    if (list.isEmpty) return; // لا تكتب كاشًا فارغًا فوق بيانات صالحة
    final p = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'schema': 1,
      'lastSync': DateTime.now().toIso8601String(),
      'items': list.map((e) => e.toJson()).toList(),
    };
    await p.setString('contacts_cache', jsonEncode(payload));
  }

  // ---------------- صلاحيات جهات الاتصال ----------------
  Future<bool> _ensureContactsPermission() async {
    final status = await Permission.contacts.status;

    if (status.isGranted) {
      setState(() => _permPermanentlyDenied = false);
      return true;
    }

    if (status.isDenied) {
      final req = await Permission.contacts.request();
      if (req.isGranted) {
        setState(() => _permPermanentlyDenied = false);
        return true;
      }
      if (req.isPermanentlyDenied) {
        setState(() => _permPermanentlyDenied = true);
        return false;
      }
      return false;
    }

    if (status.isPermanentlyDenied) {
      setState(() => _permPermanentlyDenied = true);
      return false;
    }

    // حالات أخرى (مقيّد/غير محدد)
    setState(() => _permPermanentlyDenied = status.isPermanentlyDenied);
    return status.isGranted;
  }

  // ---------------- قراءة من الجهاز + حفظ الكاش ----------------
  Future<void> _refreshFromDeviceAndSaveCache() async {
    final ok = await _ensureContactsPermission();
    if (!ok) {
      // لا نمسّ الكاش المعروض؛ نعرض بانر فقط
      setState(() => _loading = false);
      return;
    }

    try {
      final list = await fc.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      // طبّع وحوّل
      final ui = <_UiContact>[];
      for (final c in list) {
        final name = _visibleName(c.displayName);
        final phones = <String>[];
        for (final p in c.phones) {
          final raw = _orEmpty(p.number);
          final normalized = _normalizePhone(raw);
          if (normalized.isNotEmpty) phones.add(normalized);
        }
        if (phones.isEmpty) continue;
        ui.add(_UiContact(name: name, phones: phones));
      }

      // طابق الأرقام -> uid ثم uid -> username
      await _augmentWithRegistrationData(ui);
      _sortContactsWithSubscribersFirst(ui);

      // خزّن الكاش (فقط لو لدينا بيانات)
      await _saveContactsCache(ui);

      // اعرضها مرتبة (المشتركين أولًا)
      setState(() {
        _contacts
          ..clear()
          ..addAll(_sortWithSubscribersFirst(ui));
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _snack('فشل تحديث جهات الاتصال: $e');
    }
  }

  String _normalizePhone(String input) {
    // يسمح بالأرقام و "+"
    final digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('+')) return digits;
    // لو بدون +، أضف كود الدولة الافتراضي
    return '$_defaultCountryCode$digits';
  }

  // فرز: المشتركين أولًا ثم أبجدياً بالاسم
  void _sortContactsWithSubscribersFirst(List<_UiContact> list) {
    list.sort((a, b) {
      final aSub = (a.accountUid != null && a.accountUid!.isNotEmpty) ? 1 : 0;
      final bSub = (b.accountUid != null && b.accountUid!.isNotEmpty) ? 1 : 0;
      if (aSub != bSub) return bSub.compareTo(aSub); // المشترك قبل غير المشترك
      return a.name.compareTo(b.name); // بعدها ترتيب أبجدي
    });
  }

  // --------- المطابقة: users_by_phone (phone->uid) + users (uid->username) ---------
  Future<void> _augmentWithRegistrationData(List<_UiContact> ui) async {
    if (ui.isEmpty) return;
    final db = FirebaseFirestore.instance;

    // أجمع كل الأرقام الفريدة
    final allPhones = <String>{};
    for (final c in ui) {
      allPhones.addAll(c.phones);
    }
    if (allPhones.isEmpty) return;

    // 1) phone -> uid
    final phoneToUid = <String, String>{};
    final phoneChunks = _chunk(allPhones.toList(), 10);
    for (final chunk in phoneChunks) {
      final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
      for (final phone in chunk) {
        futures.add(db.doc('users_by_phone/$phone').get());
      }
      final snaps = await Future.wait(futures);
      for (int i = 0; i < snaps.length; i++) {
        final snap = snaps[i];
        if (!snap.exists) continue;
        final data = snap.data();
        if (data == null) continue;
        final uid = data['uid'] as String? ?? '';
        if (uid.isNotEmpty) {
          phoneToUid[chunk[i]] = uid;
        }
      }
    }
    if (phoneToUid.isEmpty) return;

    // 2) uid -> username (اسم العرض)
    final uids = phoneToUid.values.toSet().toList();
    final uidToName = <String, String>{};
    final uidChunks = _chunk(uids, 10);
    for (final chunk in uidChunks) {
      final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
      for (final uid in chunk) {
        futures.add(db.doc('users/$uid').get());
      }
      final snaps = await Future.wait(futures);
      for (int i = 0; i < snaps.length; i++) {
        final data = snaps[i].data();
        if (data == null) continue;
        final nm =
            (data['username'] as String?) ?? (data['name'] as String?) ?? '';
        if (nm.isNotEmpty) {
          uidToName[chunk[i]] = nm;
        }
      }
    }

    // 3) عبّئ حقول الاشتراك لكل جهة اتصال
    for (final c in ui) {
      String? matchedUid;
      for (final ph in c.phones) {
        final uid = phoneToUid[ph];
        if (uid != null && uid.isNotEmpty) {
          matchedUid = uid;
          break;
        }
      }
      if (matchedUid != null) {
        c.accountUid = matchedUid;
        c.accountName = uidToName[matchedUid] ?? '';
      }
    }
  }

  List<List<T>> _chunk<T>(List<T> input, int size) {
    final out = <List<T>>[];
    if (size <= 0) return [input];
    for (int i = 0; i < input.length; i += size) {
      final end = (i + size < input.length) ? i + size : input.length;
      out.add(input.sublist(i, end));
    }
    return out;
  }

  List<_UiContact> _sortWithSubscribersFirst(List<_UiContact> list) {
    final copy = List<_UiContact>.from(list);
    copy.sort((a, b) {
      final aSub = a.isSubscriber ? 0 : 1;
      final bSub = b.isSubscriber ? 0 : 1;
      if (aSub != bSub) return aSub - bSub;
      return a.name.compareTo(b.name);
    });
    return copy;
  }

  // ---------------- حفظ/تعديل رقمي ----------------
  Future<void> _editMyPhoneDialog() async {
    final ctrl = TextEditingController(text: _orEmpty(_myPhone));
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رقمي (E.164)'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '+9677xxxxxxx'),
            validator: (v) {
              final s = _orEmpty(v).trim();
              if (s.isEmpty) return 'أدخل رقمك';
              if (!s.startsWith('+') || s.length < 8) {
                return 'يجب أن يبدأ بـ + وبطول منطقي';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final phone = ctrl.text.trim();

              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) {
                  _snack('لا توجد جلسة دخول.');
                  return;
                }

                // users/{uid}
                await FirebaseFirestore.instance
                    .doc('users/${user.uid}')
                    .set({'phone': phone}, SetOptions(merge: true));

                // users_by_phone/{phone}
                await FirebaseFirestore.instance
                    .doc('users_by_phone/$phone')
                    .set({
                  'uid': user.uid,
                  // نكتب اسم العرض الحالي إن وجد في users
                  'username': _orEmpty(await _tryGetMyUsername(user.uid)),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                await _saveMyPhoneToPrefs(phone);
                if (mounted) Navigator.pop(context);
                _snack('تم حفظ الرقم');
              } catch (e) {
                _snack('تعذر حفظ الرقم: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _tryGetMyUsername(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
      if (!snap.exists) return null;
      final Map<String, dynamic>? data = snap.data();
      if (data == null) return null;
      return (data['username'] as String?) ?? (data['name'] as String?);
    } catch (_) {
      return null;
    }
  }

  // ---------------- فتح/إنشاء DM للمشتركين ----------------
  Future<void> _openOrCreateDmForUid(String peerUid, String title) async {
    bool wasCreating = false;
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      final targetUid = peerUid.trim();
      debugPrint(
          'DM open/create: myUid=${me ?? '(null)'}, targetUid=${targetUid.isEmpty ? '(empty)' : targetUid}');
      if (me == null || me.isEmpty) {
        _snack('لا يوجد مستخدم مسجّل.');
        return;
      }
      if (targetUid.isEmpty) {
        debugPrint('DM open/create aborted: targetUid is empty');
        _snack('لا يوجد معرف مستخدم صالح.');
        return;
      }
      if (targetUid == me) {
        _snack('هذا رقمك!');
        return;
      }

      // threadId ثابت: ترتيب UIDs ثم join بـ "_"
      final pair = [me, targetUid]..sort();
      final threadId = '${pair[0]}_${pair[1]}';
      debugPrint('DM expected chatId (threadId) = $threadId');

      final dmRef = FirebaseFirestore.instance.doc('dms/$threadId');
      final tGetStart = DateTime.now();
      final snap = await dmRef.get().timeout(const Duration(seconds: 8));
      final tGetMs = DateTime.now().difference(tGetStart).inMilliseconds;
      debugPrint('DM fetch took ${tGetMs} ms at ${dmRef.path}');
      if (!snap.exists) {
        debugPrint('DM not found, creating at ${dmRef.path}');
        wasCreating = true;
        final tSetStart = DateTime.now();
        await dmRef.set({
          'members': pair,
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 8));
        final tSetMs = DateTime.now().difference(tSetStart).inMilliseconds;
        debugPrint('DM create took ${tSetMs} ms at ${dmRef.path}');
      } else {
        debugPrint('DM exists at ${dmRef.path}');
      }

      if (!mounted) return;
      Navigator.of(context).pushNamed(
        '/chat',
        arguments: {
          'roomId': threadId,
          'root': 'dms',
          'title': title,
          'peerUid': targetUid,
        },
      );
    } on FirebaseException catch (e, st) {
      debugPrint(
        'FirebaseException while open/create DM '
        'code=${e.code}, message=${e.message ?? ''}\n$st',
      );

      if (mounted) {
        // رسالة أوضح للمستخدم، ويمكن لاحقًا تعريب حسب code إن رغبت
        _snack('تعذّر فتح/إنشاء المحادثة: ${e.code}');
      }
    } on TimeoutException catch (_, st) {
      debugPrint(
        'Timeout while open/create DM ${wasCreating ? '(create)' : '(read)'}\n$st',
      );

      if (mounted) {
        _snack(
          wasCreating
              ? 'انتهت المهلة أثناء إنشاء المحادثة.'
              : 'انتهت المهلة أثناء جلب بيانات المحادثة.',
        );
      }
    } catch (e, st) {
      debugPrint('Unexpected error while open/create DM: $e\n$st');

      if (mounted) {
        _snack('حدث خطأ غير متوقع أثناء فتح/إنشاء المحادثة.');
      }
    }
  }

  // ---------------- واجهة المستخدم ----------------
  @override
  Widget build(BuildContext context) {
    final filtered = _filter(_contacts, _searchCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('جهات الاتصال'),
        actions: [
          IconButton(
            tooltip: 'تحديث من الجهاز',
            onPressed: _refreshFromDeviceAndSaveCache,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'رقمي',
            onPressed: _editMyPhoneDialog,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'نسخ UID',
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isEmpty) {
                _snack('لا يوجد UID');
                return;
              }
              await Clipboard.setData(ClipboardData(text: uid));
              _snack('تم النسخ');
            },
            icon: const Icon(Icons.copy),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو الرقم…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_myPhone != null && _myPhone!.isNotEmpty)
            _MyPhoneTile(phone: _myPhone!, onEdit: _editMyPhoneDialog),
          if (_permPermanentlyDenied)
            _PermissionBanner(onOpenSettings: openAppSettings),
          if (_lastSuccessfulSync != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'آخر مزامنة: ${_lastSuccessfulSync!.toLocal()}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          Expanded(
            child: _loading && _contacts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : (filtered.isEmpty
                    ? const Center(child: Text('لا توجد جهات اتصال'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _ContactTile(
                          c: filtered[i],
                          onChat: filtered[i].isSubscriber
                              ? (uid, title) =>
                                  _openOrCreateDmForUid(uid, title)
                              : null, // زر دردشة فقط للمشتركين
                        ),
                      )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // مزامنة إلى السحابة هنا تعني: حفظ رقمك (من الإعدادات) ومطابقة المشتركين تتم تلقائيًا
        onPressed: _refreshFromDeviceAndSaveCache,
        icon: const Icon(Icons.sync),
        label: const Text('تحديث'),
      ),
    );
  }

  List<_UiContact> _filter(List<_UiContact> list, String queryRaw) {
    final query = _orEmpty(queryRaw).toLowerCase().trim();
    if (query.isEmpty) return list;
    return list.where((c) {
      final inName = c.name.toLowerCase().contains(query) ||
          (c.accountName ?? '').toLowerCase().contains(query);
      final inPhones =
          c.phones.any((p) => p.replaceAll(' ', '').contains(query));
      return inName || inPhones;
    }).toList();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// =================== Widgets مساعدة ===================

class _PermissionBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _PermissionBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: const Text(
        'لم يمنح النظام إذن الوصول لجهات الاتصال.\nافتح إعدادات التطبيق وفعّل "جهات الاتصال".',
      ),
      leading: const Icon(Icons.privacy_tip),
      actions: [
        TextButton(
            onPressed: onOpenSettings, child: const Text('فتح الإعدادات')),
      ],
    );
  }
}

class _MyPhoneTile extends StatelessWidget {
  final String phone;
  final VoidCallback onEdit;
  const _MyPhoneTile({required this.phone, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: ListTile(
        leading: const Icon(Icons.person),
        title: const Text('رقمي'),
        subtitle: Text(phone),
        trailing: IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
      ),
    );
  }
}

// نموذج العرض + التخزين
class _UiContact {
  final String name; // اسم جهة الاتصال من الجهاز
  final List<String> phones; // أرقام مطبّعة E.164

  // يمتلئان إذا كان صاحب الرقم مسجلًا في التطبيق
  String? accountUid; // UID
  String? accountName; // اسم العرض من users/*

  _UiContact({
    required this.name,
    required this.phones,
    this.accountUid,
    this.accountName,
  });

  bool get isSubscriber => accountUid != null && accountUid!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'phones': phones,
        'accountUid': accountUid,
        'accountName': accountName,
      };

  factory _UiContact.fromJson(Map<String, dynamic> m) {
    final rawPhones = m['phones'];
    final phones = <String>[];
    if (rawPhones is List) {
      for (final e in rawPhones) {
        if (e is String && e.isNotEmpty) phones.add(e);
      }
    }
    final nm = m['name'];
    final accUid = m['accountUid'];
    final accName = m['accountName'];
    return _UiContact(
      name: (nm is String && nm.isNotEmpty) ? nm : '(بدون اسم)',
      phones: phones,
      accountUid: (accUid is String && accUid.isNotEmpty) ? accUid : null,
      accountName: (accName is String && accName.isNotEmpty) ? accName : null,
    );
  }
}

class _ContactTile extends StatelessWidget {
  final _UiContact c;
  final void Function(String peerUid, String title)? onChat;
  const _ContactTile({required this.c, this.onChat});

  @override
  Widget build(BuildContext context) {
    final hasAccount = c.isSubscriber;
    final titleText = (c.accountName != null && c.accountName!.isNotEmpty)
        ? c.accountName!
        : c.name;

    return ListTile(
      leading: const Icon(Icons.contact_phone),
      title: Row(
        children: [
          Expanded(child: Text(titleText)),
          if (hasAccount) const SizedBox(width: 8),
          if (hasAccount)
            const Chip(
              label: Text('مشترك'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      subtitle: Text(c.phones.join(' • ')),
      trailing: hasAccount
          ? IconButton(
              tooltip: 'دردشة',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => onChat?.call(c.accountUid!, titleText),
            )
          : null,
    );
  }
}
