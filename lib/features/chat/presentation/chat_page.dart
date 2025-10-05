import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/chat_repository.dart';
import '../domain/models/message.dart';
import 'widgets/input_bar.dart';
import 'widgets/message_bubble.dart';

class ChatPage extends StatefulWidget {
  final String roomId;
  const ChatPage({super.key, required this.roomId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scrollController = ScrollController();

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatRepository>(
      builder: (context, chat, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('غرفة: ${widget.roomId}'),
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: chat.messagesStream(widget.roomId),
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? const <Message>[];
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.userId == chat.user?.uid;
                        return MessageBubble(msg: msg, isMe: isMe);
                      },
                    );
                  },
                ),
              ),
              InputBar(onSend: (text) => chat.sendMessage(widget.roomId, text)),
            ],
          ),
        );
      },
    );
  }
}
