import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/message.dart';

class ChatRepository extends ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  ChatRepository(this._auth, this._db);

  String _currentRoomId = 'general';
  String get currentRoomId => _currentRoomId;

  String? _username;
  String? get username => _username;

  User? get user => _auth.currentUser;

  Future<void> init() async {
    // Load stored username
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username');
    // Ensure signed-in (anonymous)
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    notifyListeners();
  }

  Future<void> setUsername(String name) async {
    _username = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', _username!);
    notifyListeners();
  }

  void joinRoom(String roomId) {
    _currentRoomId = roomId;
    notifyListeners();
  }

  Future<void> createAndJoinRoom(String roomId) async {
    final id = roomId.trim();
    if (id.isEmpty) return;
    await _db.collection('rooms').doc(id).set({
      'name': id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': '',
    }, SetOptions(merge: true));
    joinRoom(id);
  }

  Stream<List<String>> roomsStream() {
    return _db.collection('rooms')
      .orderBy('updatedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.id).toList());
  }

  Stream<List<Message>> messagesStream(String roomId) {
    return _db.collection('rooms').doc(roomId).collection('messages')
      .orderBy('ts', descending: false)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs.map((d) => Message.fromFirestore(d.id, roomId, d.data())).toList());
  }

  Future<void> sendMessage(String roomId, String text) async {
    final uid = user?.uid ?? 'unknown';
    final name = _username ?? 'مجهول';
    final msgRef = _db.collection('rooms').doc(roomId).collection('messages').doc();
    await msgRef.set({
      'userId': uid,
      'username': name,
      'text': text.trim(),
      'ts': FieldValue.serverTimestamp(),
    });
    // Update room metadata
    await _db.collection('rooms').doc(roomId).set({
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': text.trim().substring(0, text.trim().length.clamp(0, 40)),
    }, SetOptions(merge: true));
  }
}
