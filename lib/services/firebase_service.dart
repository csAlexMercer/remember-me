import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/remember_item.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Authentication
  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      print("Error signing in anonymously: \$e");
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Firestore
  CollectionReference get _itemsCollection {
    if (currentUser == null) throw Exception("User not logged in");
    return _firestore.collection('users').doc(currentUser!.uid).collection('items');
  }

  Stream<List<RememberItem>> getActiveItems() {
    if (currentUser == null) return const Stream.empty();
    return _itemsCollection
        .where('isAsleep', isEqualTo: false)
        .orderBy('priority', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RememberItem.fromFirestore(doc))
            .toList());
  }

  Stream<List<RememberItem>> getAsleepItems() {
    if (currentUser == null) return const Stream.empty();
    return _itemsCollection
        .where('isAsleep', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RememberItem.fromFirestore(doc))
            .toList());
  }

  Future<void> addItem(RememberItem item) async {
    if (currentUser == null) return;
    await _itemsCollection.add(item.toFirestore());
  }

  Future<void> updateItem(RememberItem item) async {
    if (currentUser == null) return;
    await _itemsCollection.doc(item.id).update(item.toFirestore());
  }

  Future<void> deleteItem(String id) async {
    if (currentUser == null) return;
    await _itemsCollection.doc(id).delete();
  }

  Future<void> toggleSleepStatus(RememberItem item) async {
    await updateItem(item.copyWith(isAsleep: !item.isAsleep));
  }
}
