import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> saveMyPhoneE164(String phoneE164, {String? displayName}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw 'Not signed in';

  final fs = FirebaseFirestore.instance;
  final batch = fs.batch();

  // 1) users/{uid}
  final userDoc = fs.collection('users').doc(uid);
  batch.set(
      userDoc,
      {
        'phone': phoneE164,
        if (displayName != null) 'username': displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true));

  // 2) users_by_phone/{+E164}
  final phoneDoc = fs.collection('users_by_phone').doc(phoneE164);
  batch.set(
      phoneDoc,
      {
        'uid': uid,
        if (displayName != null) 'displayName': displayName,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true));

  await batch.commit();
}
