import 'package:flutter/material.dart';
import '../../domain/models/message.dart';

class MessageBubble extends StatelessWidget {
  final Message msg;
  final bool isMe;
  const MessageBubble({super.key, required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isMe ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceVariant,
          borderRadius: isMe
              ? BorderRadius.only(
                  topLeft: radius.topLeft,
                  topRight: radius.topRight,
                  bottomLeft: radius.bottomLeft,
                )
              : BorderRadius.only(
                  topLeft: radius.topLeft,
                  topRight: radius.topRight,
                  bottomRight: radius.bottomRight,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe)
              Text(
                msg.username,
                style: theme.textTheme.labelMedium,
              ),
            Text(msg.text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _friendlyTime(msg.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
