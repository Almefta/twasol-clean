import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads a file to Firebase Storage and returns its download URL.
  /// [path] is the full path in Firebase Storage (e.g., 'user_profiles/userId/profile.jpg').
  /// [file] is the file to upload.
  Future<String?> uploadFile(String path, File file) async {
    try {
      final ref = _storage.ref().child(path);
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask.whenComplete(() => null);
      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        print('Firebase Storage Error: ${e.message}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading file: $e');
      }
      return null;
    }
  }

  /// Deletes a file from Firebase Storage.
  /// [url] is the download URL of the file to delete.
  Future<void> deleteFileByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        print('Firebase Storage Error: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting file: $e');
      }
    }
  }
}
