import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/remember_item.dart';
import '../services/notification_service.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Authentication ────────────────────────────────────────

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with Google using the new google_sign_in 7.x API.
  Future<User?> signInWithGoogle() async {
    try {
      // Authenticate with Google
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // Build Firebase credential using the idToken
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // Sign in directly
      final userCredential = await _auth.signInWithCredential(credential);
      await _updateUserProfile(userCredential.user, googleUser);
      return _auth.currentUser;
    } catch (e) {
      print("Error signing in with Google: $e");
      return null;
    }
  }

  Future<void> _updateUserProfile(
    User? user,
    GoogleSignInAccount googleUser,
  ) async {
    if (user != null) {
      bool updated = false;
      if (user.displayName == null ||
          user.displayName != googleUser.displayName) {
        await user.updateDisplayName(googleUser.displayName);
        updated = true;
      }
      if (user.photoURL == null || user.photoURL != googleUser.photoUrl) {
        await user.updatePhotoURL(googleUser.photoUrl);
        updated = true;
      }
      if (updated) {
        await user.reload();
      }
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;

    final userDoc = _firestore.collection('users').doc(user.uid);
    final itemsSnapshot = await userDoc.collection('items').get();

    for (final doc in itemsSnapshot.docs) {
      final item = RememberItem.fromFirestore(doc);
      await NotificationService().cancelReminder(item.notificationId);
    }

    final batch = _firestore.batch();
    for (final doc in itemsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(userDoc);
    await batch.commit();

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') {
        rethrow;
      }
    } finally {
      await GoogleSignIn.instance.signOut();
      await _auth.signOut();
    }
  }

  // ─── Firestore ─────────────────────────────────────────────

  CollectionReference get _itemsCollection {
    if (currentUser == null) throw Exception("User not logged in");
    return _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('items');
  }

  Stream<List<RememberItem>> getActiveItems() {
    if (currentUser == null) return const Stream.empty();
    return _itemsCollection
        .where('isAsleep', isEqualTo: false)
        .orderBy('priority', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RememberItem.fromFirestore(doc))
              .toList(),
        );
  }

  Stream<List<RememberItem>> getAsleepItems() {
    if (currentUser == null) return const Stream.empty();
    return _itemsCollection
        .where('isAsleep', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RememberItem.fromFirestore(doc))
              .toList(),
        );
  }

  Future<List<RememberItem>> getActiveItemsOnce() async {
    if (currentUser == null) return [];
    final snapshot = await _itemsCollection
        .where('isAsleep', isEqualTo: false)
        .orderBy('priority', descending: true)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => RememberItem.fromFirestore(doc)).toList();
  }

  /// On app open, ensure notification-eligible awake items have reminders scheduled.
  Future<void> runStartupReminderCheck() async {
    if (currentUser == null) return;

    final notifService = NotificationService();
    final activeItems = await getActiveItemsOnce();
    final now = DateTime.now();

    for (final item in activeItems.where((item) => item.shouldNotify)) {
      DateTime? nextDate = item.nextScheduledReminder;

      if (nextDate == null || !nextDate.isAfter(now)) {
        nextDate = item.calculateNextReminderDate();
        if (nextDate != null) {
          await updateItem(item.copyWith(nextScheduledReminder: nextDate));
        }
      }

      if (nextDate != null) {
        await notifService.scheduleReminder(
          id: item.notificationId,
          title: 'Remember: ${item.title}',
          body: item.description.isNotEmpty
              ? item.description
              : 'Time to revisit this thought.',
          scheduledDate: nextDate,
        );
      }
    }
  }

  /// Add a new item and return its Firestore document ID.
  Future<String?> addItem(RememberItem item) async {
    if (currentUser == null) return null;
    final docRef = await _itemsCollection.add(item.toFirestore());
    return docRef.id;
  }

  Future<void> updateItem(RememberItem item) async {
    if (currentUser == null) return;
    await _itemsCollection.doc(item.id).update(item.toFirestore());
  }

  Future<void> deleteItem(String id) async {
    if (currentUser == null) return;
    // Cancel any pending notification for this item
    await NotificationService().cancelReminder(id.hashCode.abs());
    await _itemsCollection.doc(id).delete();
  }

  /// Toggle sleep status for an item.
  /// When putting to sleep: cancel pending notification.
  /// When waking up: reschedule with the multiplier effect.
  Future<void> toggleSleepStatus(RememberItem item) async {
    final willSleep = !item.isAsleep;
    final notifService = NotificationService();

    if (willSleep) {
      // Putting to sleep — cancel notification and halt progression
      await notifService.cancelReminder(item.notificationId);
      await updateItem(
        item.copyWith(isAsleep: true, nextScheduledReminder: null),
      );
    } else {
      // Waking up — reschedule with multiplier effect
      final nextDate = item.calculateNextReminderDate();
      if (nextDate != null) {
        await notifService.scheduleReminder(
          id: item.notificationId,
          title: 'Remember: ${item.title}',
          body: item.description.isNotEmpty
              ? item.description
              : 'Time to revisit this thought.',
          scheduledDate: nextDate,
        );
      }
      await updateItem(
        item.copyWith(isAsleep: false, nextScheduledReminder: nextDate),
      );
    }
  }

  /// Called when a reminder fires. Increments the count and schedules the next one.
  Future<void> handleReminderFired(RememberItem item) async {
    final updatedItem = item.copyWith(
      reminderCount: item.reminderCount + 1,
      lastReminderSent: DateTime.now(),
    );

    final nextDate = updatedItem.calculateNextReminderDate();
    final finalItem = updatedItem.copyWith(nextScheduledReminder: nextDate);

    await updateItem(finalItem);

    if (nextDate != null && !finalItem.isAsleep) {
      await NotificationService().scheduleReminder(
        id: finalItem.notificationId,
        title: 'Remember: ${finalItem.title}',
        body: finalItem.description.isNotEmpty
            ? finalItem.description
            : 'Time to revisit this thought.',
        scheduledDate: nextDate,
      );
    }
  }
}
