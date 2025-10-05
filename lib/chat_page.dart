// lib/chat_page.dart
// شاشة الدردشة (DM/Room) مع ميزات متقدّمة:
// - Typing indicator
// - Delivered/Seen
// - Reply + preview
// - Reactions
// - Date headers
// - Pagination
// - Mute thread

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// قائمة الإيموجيز المسموحة (يمكنك تعديلها بحرية)
const kReactions = ['👍', '❤️', '😂', '😮', '👏'];

// ===== نموذج قراءة الرسالة مع التفاعلات =====
class ChatMessage {
  final String id;
  final String userId;
  final String? username;
  final String? text;
  final Timestamp ts;

  // reactions: { '👍': ['uid1','uid2'], '❤️': ['uid7'] }
  final Map<String, List<String>> reactions;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.ts,
    required this.reactions,
    this.username,
    this.text,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'username': username,
      'text': text,
      'ts': ts,
      'reactions': reactions.map((k, v) => MapEntry(k, v)),
    };
  }

  factory ChatMessage.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? {};

    // ✅ لا نحولها إلى List — بل نقرأها كـ Map
    final raw = (data['reactions'] as Map<String, dynamic>?) ?? {};
    final map = <String, List<String>>{};
    raw.forEach((k, v) {
      final list = (v is List) ? v.cast<String>() : <String>[];
      map[k] = list;
    });

    return ChatMessage(
      id: snap.id,
      userId: (data['userId'] as String?) ?? '',
      username: (data['username'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      ts: (data['ts'] as Timestamp?) ?? Timestamp.now(),
      reactions: map,
    );
  }
}

// ===== دالة التبديل (إضافة/إزالة) تفاعل للمستخدم الحالي على رسالة =====
Future<void> toggleReaction({
  required String rootCollection, // 'dms' أو 'rooms'
  required String threadOrRoomId, // threadId / roomId
  required String messageId,
  required String emoji, // من kReactions
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final db = FirebaseFirestore.instance;
  final msgRef = db
      .collection(rootCollection)
      .doc(threadOrRoomId)
      .collection('messages')
      .doc(messageId);

  await db.runTransaction((tx) async {
    final snap = await tx.get(msgRef);
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    final reactions = (data['reactions'] as Map<String, dynamic>?) ?? {};

    final currentList = ((reactions[emoji] ?? []) as List).cast<String>();
    final has = currentList.contains(uid);

    final newList = [...currentList];
    if (has) {
      newList.remove(uid);
    } else {
      newList.add(uid);
    }

    reactions[emoji] = newList;

    // (اختياري) نحفظ عدّادات سريعة للعرض: { '👍': 2, '❤️': 1 }
    final counts = <String, int>{};
    reactions.forEach((k, v) => counts[k] = (v as List).length);

    tx.update(msgRef, {
      'reactions': reactions,
      'reactionCounts': counts,
    });
  });
}

// ===== ودجت عرض الرسالة مع التفاعلات =====
// استبدل MessageTile لديك بهذا أو أدرجه داخل الـ build لعنصر الرسالة.
class MessageTile extends StatelessWidget {
  final ChatMessage msg;
  final bool mine;
  final String root; // 'dms' أو 'rooms'
  final String threadId; // threadId/roomId

  const MessageTile({
    super.key,
    required this.msg,
    required this.mine,
    required this.root,
    required this.threadId,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final chips = <Widget>[];

    // نبني شارات التفاعل مع العدّاد
    msg.reactions.forEach((emoji, users) {
      final count = users.length;
      if (count == 0) return;
      chips.add(Padding(
        padding: const EdgeInsetsDirectional.only(end: 4, top: 4),
        child: Chip(
          visualDensity: VisualDensity.compact,
          label: Text('$emoji $count'),
        ),
      ));
    });

    return GestureDetector(
      onLongPress: () => _showReactionsSheet(context),
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine
                ? Colors.deepPurple.withOpacity(.12)
                : Colors.grey.withOpacity(.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if ((msg.username ?? '').isNotEmpty)
                Text(msg.username!,
                    style:
                        style?.copyWith(fontSize: 12, color: Colors.grey[600])),
              if ((msg.text ?? '').isNotEmpty) Text(msg.text!, style: style),
              if (chips.isNotEmpty) Wrap(children: chips),
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          children: [
            for (final e in kReactions)
              IconButton(
                iconSize: 28,
                onPressed: () async {
                  Navigator.pop(context);
                  await toggleReaction(
                    rootCollection: root,
                    threadOrRoomId: threadId,
                    messageId: msg.id,
                    emoji: e,
                  );
                },
                icon: Text(e, style: const TextStyle(fontSize: 24)),
                tooltip: 'React $e',
              ),
          ],
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String username;
  final String roomId;
  final String rootCollection; // 'dms' أو 'rooms'
  final String? roomTitle;
  final String? peerUid;

  const ChatPage({
    super.key,
    required this.username,
    required this.roomId,
    required this.rootCollection,
    this.roomTitle,
    this.peerUid,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _msgKeys = {}; // لكل رسالة مفتاح للتمرير

  String get _root => widget.rootCollection;
  String get _roomId => widget.roomId;

  String? _myUid;

  // Pagination
  static const int _pageSize = 25;
  DocumentSnapshot? _lastDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Reply state
  Map<String, dynamic>? _replyingTo; // {id, name, text}

  // Typing
  Timer? _typingTimer;
  final Duration _typingHold = const Duration(seconds: 3);

  // Mute
  bool _muted = false;

  // Stream
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;

  // Sending state
  final _isSending = ValueNotifier<bool>(false);

  // === Emoji + Scroll state ===
  bool _showEmoji = false; // هل لوحة الإيموجي ظاهرة؟
  final FocusNode _inputFocus = FocusNode(); // للتحكم بلوحة المفاتيح
  // استخدم نفس المتحكم الحالي للتمرير
  ScrollController get _scrollC => _scrollCtrl; // تمرير الرسائل

  // إظهار/إخفاء لوحة الإيموجي
  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _inputFocus.requestFocus(); // رجّع التركيز لحقل الكتابة
    } else {
      _inputFocus.unfocus(); // أغلق الكيبورد
      setState(() => _showEmoji = true);
    }
  }

  // تمرير لأسفل مع احترام المستخدم لو كان يتصفح أعلى القائمة
  void _scrollToBottom({bool animated = true}) {
    if (!_scrollC.hasClients) return;
    final atBottom =
        _scrollC.position.pixels >= (_scrollC.position.maxScrollExtent - 100); // هامش 100px
    if (!atBottom && animated == false) return; // لا نجبر التمرير إن المستخدم بعيد

    final target = _scrollC.position.maxScrollExtent;
    if (animated) {
      _scrollC.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollC.jumpTo(target);
    }
  }

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid;
    _initThreadState();
    _setupStream();
    _scrollCtrl.addListener(_onScroll);
    _markSeenDebounced();

    // مرقاب تغيّر النص: عند بدء الكتابة نمرّر للأسفل بلطف (إن كان المستخدم قريبًا من القاع)
    _msgCtrl.addListener(() {
      // لا نفتح الإيموجي هنا؛ فقط تمرير بسيط إن كان قريبًا من القاع
      if (_scrollC.hasClients) {
        final nearBottom =
            _scrollC.position.pixels >= (_scrollC.position.maxScrollExtent - 200);
        if (nearBottom) {
          // تأخير فريم ليتم حساب الارتفاعات بعد إدخال محارف جديدة
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom(animated: true);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _typingTimer?.cancel();
    _isSending.dispose();
    _inputFocus.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initThreadState() async {
    final rootRef = FirebaseFirestore.instance.collection(_root).doc(_roomId);
    final snap = await rootRef.get();
    final data = snap.data();
    if (data != null) {
      final mutedMap = (data['muted'] as Map?)?.cast<String, dynamic>();
      if (mutedMap != null && _myUid != null) {
        setState(() => _muted = (mutedMap[_myUid!] == true));
      }
    }
  }

  void _setupStream() {
    final ref = FirebaseFirestore.instance
        .collection(_root)
        .doc(_roomId)
        .collection('messages')
        .orderBy('ts', descending: false)
        .limitToLast(_pageSize);

    _stream = ref.snapshots();

    _stream!.listen((snap) {
      if (snap.docs.isNotEmpty) {
        _lastDoc = snap.docs.first;
      }
      _markSeenDebounced();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _autoScrollIfNearBottom());
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    if (_lastDoc == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final olderSnap = await FirebaseFirestore.instance
          .collection(_root)
          .doc(_roomId)
          .collection('messages')
          .orderBy('ts', descending: false)
          .endBeforeDocument(_lastDoc!)
          .limitToLast(_pageSize)
          .get();

      if (olderSnap.docs.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      _lastDoc = olderSnap.docs.first;
      setState(() => _isLoadingMore = false);
    } catch (e) {
      debugPrint('Error loading more messages: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels <= 40) {
      _loadMore();
    }
  }

  void _autoScrollIfNearBottom() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final offset = _scrollCtrl.offset;
    if ((max - offset) < 140) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _myUid == null) return;

    _isSending.value = true;
    try {
      final msg = <String, dynamic>{
        'text': text,
        'userId': _myUid!,
        'username': widget.username,
        'ts': FieldValue.serverTimestamp(),
        'deliveredTo': <String>[],
        'seenBy': <String>[],
      };
      if (_replyingTo != null) {
        msg['replyTo'] = {
          'id': _replyingTo!['id'],
          'name': _replyingTo!['name'],
          'text': _replyingTo!['text'],
        };
      }

      await FirebaseFirestore.instance
          .collection(_root)
          .doc(_roomId)
          .collection('messages')
          .add(msg);

      _msgCtrl.clear();
      setState(() => _replyingTo = null);
      _sendTyping(false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الإرسال: $e')),
      );
    } finally {
      if (mounted) _isSending.value = false;
    }
  }

  // قائمة الضغط المطوّل (رد/حذف)
  Future<void> _onMessageLongPress(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (_showEmoji) setState(() => _showEmoji = false);
    _inputFocus.unfocus();
    final data = doc.data();
    final isMine = (data['userId'] == _myUid);

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('الرد'),
            onTap: () => Navigator.pop(context, 'reply'),
          ),
          if (isMine)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('حذف'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ]),
      ),
    );

    if (choice == 'reply') {
      setState(() {
        _replyingTo = {
          'id': doc.id,
          'name': (data['username'] as String?) ?? 'مستخدم',
          'text': (data['text'] as String?) ?? '',
        };
      });
      return;
    }

    if (choice == 'delete' && isMine) {
      await doc.reference.delete();
      // بديل الحذف الناعم:
      // await doc.reference.update({'isDeleted': true, 'text': ''});
    }
  }

  // Delivered/Seen
  Timer? _seenTimer;
  void _markSeenDebounced() {
    _seenTimer?.cancel();
    _seenTimer = Timer(const Duration(milliseconds: 500), _markSeenNow);
  }

  Future<void> _markSeenNow() async {
    if (_myUid == null) return;
    try {
      final qs = await FirebaseFirestore.instance
          .collection(_root)
          .doc(_roomId)
          .collection('messages')
          .orderBy('ts', descending: true)
          .limit(50)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final d in qs.docs) {
        final data = d.data();
        final from = (data['userId'] as String?) ?? '';
        if (from == _myUid) continue;
        final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? <String>[];
        if (!seenBy.contains(_myUid)) {
          batch.update(d.reference, {
            'seenBy': FieldValue.arrayUnion([_myUid]),
            'deliveredTo': FieldValue.arrayUnion([_myUid]),
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking messages seen: $e');
    }
  }

  void _onTypingChanged(String val) {
    _sendTyping(true);
    _typingTimer?.cancel();
    _typingTimer = Timer(_typingHold, () => _sendTyping(false));
    setState(() {});
  }

  Future<void> _sendTyping(bool typing) async {
    if (_myUid == null) return;
    final ref = FirebaseFirestore.instance
        .collection(_root)
        .doc(_roomId)
        .collection('typing')
        .doc(_myUid);
    await ref.set(
      {'typing': typing, 'ts': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Stream<bool> _otherIsTypingStream() {
    final col = FirebaseFirestore.instance
        .collection(_root)
        .doc(_roomId)
        .collection('typing');

    return col.snapshots().map((qs) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final d in qs.docs) {
        if (d.id == _myUid) continue;
        final data = d.data();
        final typing = data['typing'] == true;
        final ts = (data['ts'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        if (typing && (now - ts) < 5000) return true;
      }
      return false;
    });
  }

  Future<void> _toggleMute() async {
    if (_myUid == null) return;
    final ref = FirebaseFirestore.instance.collection(_root).doc(_roomId);
    await ref.set({
      'muted': {_myUid!: !_muted}
    }, SetOptions(merge: true));
    setState(() => _muted = !_muted);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_muted ? 'تم كتم المحادثة' : 'تم إلغاء الكتم')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.roomTitle ?? (widget.peerUid ?? _roomId);
    return WillPopScope(
      onWillPop: () async {
        if (_showEmoji) {
          setState(() => _showEmoji = false);
          _inputFocus.requestFocus();
          return false;
        }
        return true;
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: _muted ? 'إلغاء الكتم' : 'كتم المحادثة',
            icon: Icon(_muted ? Icons.notifications_off : Icons.notifications),
            onPressed: _toggleMute,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: StreamBuilder<bool>(
            stream: _otherIsTypingStream(),
            builder: (context, snap) {
              final typing = snap.data == true;
              return AnimatedOpacity(
                opacity: typing ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('يكتب الآن…', style: TextStyle(fontSize: 12)),
                ),
              );
            },
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _stream == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _stream,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(child: Text('خطأ: ${snap.error}'));
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text('لا توجد رسائل بعد'));
                      }

                      final items = _groupByDate(docs);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom(animated: true);
                      });
                      return ListView.builder(
                        controller: _scrollC,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                        itemCount: items.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoadingMore && index == 0) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final i = _isLoadingMore ? index - 1 : index;
                          final item = items[i];
                          if (item.isHeader) {
                            // ⬅⬅ إصلاح الخطأ: تعريف _DateHeader بالأسفل
                            return _DateHeader(text: item.headerText!);
                          }

                      final doc = item.doc!;
                      final data = doc.data();
                      final mine = (data['userId'] == _myUid);
                      final msgId = doc.id;
                      _msgKeys[msgId] = _msgKeys[msgId] ?? GlobalKey();

                      return Container(
                        key: _msgKeys[msgId],
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        child: GestureDetector(
                          onLongPress: () => _onMessageLongPress(doc),
                          child: _MessageBubble(
                            data: data,
                            isMine: mine,
                            onTapQuoted: (quoted) => _jumpToMessage(quoted),
                          ),
                        ),
                      );
                        },
                      );
                    },
                  ),
          ),
          _buildReplyPreview(),
          _buildComposer(),
          Offstage(
            offstage: !_showEmoji,
            child: SizedBox(
              height: kIsWeb ? 320 : 280,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  _msgCtrl.text += emoji.emoji;
                },
                onBackspacePressed: () {
                  final t = _msgCtrl.text;
                  if (t.isEmpty) return;
                  final sel = _msgCtrl.selection;
                  if (sel.isValid && sel.start > 0) {
                    final start = sel.start;
                    final end = sel.end;
                    final newText = t.replaceRange(start - 1, end, '');
                    _msgCtrl
                      ..text = newText
                      ..selection = TextSelection.collapsed(offset: start - 1);
                  } else if (!sel.isValid && t.isNotEmpty) {
                    _msgCtrl.text = t.substring(0, t.length - 1);
                    _msgCtrl.selection =
                        TextSelection.collapsed(offset: _msgCtrl.text.length);
                  }
                },
                config: const Config(
                  emojiViewConfig: EmojiViewConfig(
                    emojiSizeMax: 28,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingTo == null) return const SizedBox.shrink();
    final txt = (_replyingTo!['text'] as String?) ?? '';
    final by = (_replyingTo!['name'] as String?) ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      color: Colors.black12,
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text('$by: $txt', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  // التمرير إلى الرسالة المُقتبسة
  void _jumpToMessage(String quotedMsgId) {
    final key = _msgKeys[quotedMsgId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.2,
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: const Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'إيموجي',
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: _toggleEmoji,
            ),
            IconButton(
              tooltip: 'مرفق',
              icon: const Icon(Icons.attach_file),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'رفع المرفقات يحتاج تمكين Firebase Storage (خطة Blaze).'),
                  ),
                );
              },
            ),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                focusNode: _inputFocus,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: _onTypingChanged,
                onTap: () {
                  if (_showEmoji) setState(() => _showEmoji = false);
                },
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<bool>(
              valueListenable: _isSending,
              builder: (context, isSending, child) {
                return IconButton(
                  tooltip: 'إرسال',
                  icon: isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: isSending || _msgCtrl.text.isEmpty
                      ? null
                      : () async {
                          await _send();
                          _scrollToBottom(animated: true);
                        },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ======= تجميع الرسائل حسب التاريخ =======
  List<_ListItem> _groupByDate(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <_ListItem>[];
    String? lastDateKey;

    void pushHeaderIfNeeded(Timestamp? ts) {
      final dayKey = _dateKey(ts);
      if (dayKey != lastDateKey) {
        lastDateKey = dayKey;
        out.add(_ListItem.header(_formatDateHeader(ts)));
      }
    }

    for (final d in docs) {
      final data = d.data();
      final ts = data['ts'] as Timestamp?;
      pushHeaderIfNeeded(ts);
      out.add(_ListItem.doc(d));
    }
    return out;
  }

  String _dateKey(Timestamp? ts) {
    final dt = ts?.toDate() ?? DateTime.now();
    return '${dt.year}-${dt.month}-${dt.day}';
  }

  String _formatDateHeader(Timestamp? ts) {
    final dt = ts?.toDate() ?? DateTime.now();
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return 'اليوم';
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    if (isYesterday) return 'أمس';
    return '${dt.year}/${dt.month}/${dt.day}';
  }
}

// عنصر لقائمة الرسائل (إما عنوان تاريخ أو وثيقة رسالة)
class _ListItem {
  final bool isHeader;
  final String? headerText;
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;

  _ListItem.header(this.headerText)
      : isHeader = true,
        doc = null;

  _ListItem.doc(this.doc)
      : isHeader = false,
        headerText = null;
}

// ⬅⬅ التعريف المفقود سابقًا
class _DateHeader extends StatelessWidget {
  final String text;
  const _DateHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// فقاعة الرسالة مع دعم الاقتباس والنص المحذوف
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMine;
  final void Function(String quotedMsgId)? onTapQuoted;
  const _MessageBubble({required this.data, required this.isMine, this.onTapQuoted});

  @override
  Widget build(BuildContext context) {
    final isDeleted = (data['isDeleted'] == true);
    final text = (data['text'] as String?) ?? '';
    final reply = data['replyTo'] as Map<String, dynamic>?; // {id, name, text}

    return Column(
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (reply != null)
          InkWell(
            onTap: reply['id'] != null ? () => onTapQuoted?.call(reply['id'] as String) : null,
            child: Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
                border: const Border(left: BorderSide(color: Colors.blue, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((reply['name'] as String?) ?? '…', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text((reply['text'] as String?) ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMine ? const Color(0xFFF3E8FF) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: Text(isDeleted ? 'تم حذف هذه الرسالة' : text),
        ),
      ],
    );
  }
}
