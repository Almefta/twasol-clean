import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../chat/data/chat_repository.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatRepository>(builder: (context, chat, _) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('غرف الدردشة'),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<String>>(
                stream: chat.roomsStream(),
                builder: (context, snapshot) {
                  final rooms = snapshot.data ?? const <String>[];
                  if (rooms.isEmpty) {
                    return const Center(child: Text('لا توجد غرف بعد. أنشئ غرفة جديدة.'));
                  }
                  return ListView(
                    children: [
                      for (final room in rooms)
                        ListTile(
                          title: Text(room),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            chat.joinRoom(room);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatPage(roomId: room),
                            ));
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'أنشئ غرفة جديدة',
                        hintText: 'مثال: team-android',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final id = _controller.text.trim();
                      if (id.isEmpty) return;
                      await chat.createAndJoinRoom(id);
                      _controller.clear();
                      if (!mounted) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatPage(roomId: id),
                      ));
                    },
                    child: const Text('إنشاء/دخول'),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    });
  }
}
