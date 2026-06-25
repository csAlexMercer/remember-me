import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/remember_item.dart';
import '../services/notification_service.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[FirebaseService] $message');
    }
  }

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
    if (user == null) {
      _log('deleteAccount: no current user');
      return;
    }

    _log('deleteAccount: starting for uid=${user.uid}');

    final userDoc = _firestore.collection('users').doc(user.uid);
    final itemsSnapshot = await userDoc.collection('items').get();
    _log('deleteAccount: loaded ${itemsSnapshot.docs.length} items');

    for (final doc in itemsSnapshot.docs) {
      final item = RememberItem.fromFirestore(doc);
      _log(
        'deleteAccount: canceling notification id=${item.notificationId} item=${item.id}',
      );
      await NotificationService().cancelReminder(item.notificationId);
    }

    final batch = _firestore.batch();
    for (final doc in itemsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(userDoc);
    await batch.commit();
    _log('deleteAccount: firestore cleanup committed');

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
    if (currentUser == null) {
      _log('runStartupReminderCheck: skipped, no current user');
      return;
    }

    final notifService = NotificationService();
    final activeItems = await getActiveItemsOnce();
    final now = DateTime.now();

    _log(
      'runStartupReminderCheck: start activeItems=${activeItems.length} now=${now.toIso8601String()} notificationsAllowed=${notifService.notificationsAllowed} exactAlarmsAllowed=${notifService.exactAlarmsAllowed}',
    );

    for (final item in activeItems.where((item) => item.shouldNotify)) {
      _log(
        'runStartupReminderCheck: item=${item.id} title="${item.title}" nextScheduledReminder=${item.nextScheduledReminder?.toIso8601String()} reminderCount=${item.reminderCount} isAsleep=${item.isAsleep}',
      );
      DateTime? nextDate = item.nextScheduledReminder;

      if (nextDate == null || !nextDate.isAfter(now)) {
        _log(
          'runStartupReminderCheck: recalculating next date for item=${item.id}',
        );
        nextDate = item.calculateNextReminderDate();
        if (nextDate != null) {
          _log(
            'runStartupReminderCheck: updating Firestore nextScheduledReminder=${nextDate.toIso8601String()} for item=${item.id}',
          );
          await updateItem(item.copyWith(nextScheduledReminder: nextDate));
        }
      }

      if (nextDate != null) {
        _log(
          'runStartupReminderCheck: scheduling item=${item.id} for ${nextDate.toIso8601String()}',
        );
        await notifService.scheduleReminder(
          id: item.notificationId,
          title: 'Remember: ${item.title}',
          body: item.description.isNotEmpty
              ? item.description
              : 'Time to revisit this thought.',
          scheduledDate: nextDate,
          payload: item.id,
        );
      } else {
        _log(
          'runStartupReminderCheck: no schedulable date for item=${item.id}',
        );
      }
    }

    _log('runStartupReminderCheck: complete');
  }

  /// Add a new item and return its Firestore document ID.
  Future<String?> addItem(RememberItem item) async {
    if (currentUser == null) {
      _log('addItem: skipped, no current user');
      return null;
    }

    _log(
      'addItem: creating title="${item.title}" priority=${item.priority} shouldNotify=${item.shouldNotify}',
    );
    final docRef = await _itemsCollection.add(item.toFirestore());
    _log('addItem: created docId=${docRef.id}');
    return docRef.id;
  }

  Future<void> updateItem(RememberItem item) async {
    if (currentUser == null) {
      _log('updateItem: skipped for item=${item.id}, no current user');
      return;
    }

    _log(
      'updateItem: writing item=${item.id} nextScheduledReminder=${item.nextScheduledReminder?.toIso8601String()} reminderCount=${item.reminderCount} isAsleep=${item.isAsleep}',
    );
    await _itemsCollection.doc(item.id).update(item.toFirestore());
    _log('updateItem: complete for item=${item.id}');
  }

  Future<void> deleteItem(String id) async {
    if (currentUser == null) {
      _log('deleteItem: skipped for id=$id, no current user');
      return;
    }
    // Cancel any pending notification for this item
    _log('deleteItem: canceling notification for id=$id');
    await NotificationService().cancelReminder(id.hashCode.abs());
    _log('deleteItem: deleting firestore doc id=$id');
    await _itemsCollection.doc(id).delete();
    _log('deleteItem: complete for id=$id');
  }

  /// Toggle sleep status for an item.
  /// When putting to sleep: cancel pending notification.
  /// When waking up: reschedule with the multiplier effect.
  Future<void> toggleSleepStatus(RememberItem item) async {
    final willSleep = !item.isAsleep;
    final notifService = NotificationService();

    _log(
      'toggleSleepStatus: item=${item.id} willSleep=$willSleep reminderCount=${item.reminderCount} nextScheduledReminder=${item.nextScheduledReminder?.toIso8601String()}',
    );

    if (willSleep) {
      // Putting to sleep — cancel notification and halt progression
      _log('toggleSleepStatus: canceling notification for item=${item.id}');
      await notifService.cancelReminder(item.notificationId);
      await updateItem(
        item.copyWith(isAsleep: true, nextScheduledReminder: null),
      );
    } else {
      // Waking up — reschedule with multiplier effect
      final nextDate = item.calculateNextReminderDate();
      _log(
        'toggleSleepStatus: computed nextDate=${nextDate?.toIso8601String()} for item=${item.id}',
      );
      if (nextDate != null) {
        _log('toggleSleepStatus: scheduling item=${item.id}');
        await notifService.scheduleReminder(
          id: item.notificationId,
          title: 'Remember: ${item.title}',
          body: item.description.isNotEmpty
              ? item.description
              : 'Time to revisit this thought.',
          scheduledDate: nextDate,
          payload: item.id,
        );
      }
      await updateItem(
        item.copyWith(isAsleep: false, nextScheduledReminder: nextDate),
      );
    }
  }

  /// Called when a reminder fires. Increments the count and schedules the next one.
  Future<void> handleReminderFired(RememberItem item) async {
    _log(
      'handleReminderFired: item=${item.id} reminderCount=${item.reminderCount} isAsleep=${item.isAsleep}',
    );
    final updatedItem = item.copyWith(
      reminderCount: item.reminderCount + 1,
      lastReminderSent: DateTime.now(),
    );

    final nextDate = updatedItem.calculateNextReminderDate();
    final finalItem = updatedItem.copyWith(nextScheduledReminder: nextDate);

    _log(
      'handleReminderFired: updating item=${item.id} nextDate=${nextDate?.toIso8601String()}',
    );

    await updateItem(finalItem);

    if (nextDate != null && !finalItem.isAsleep) {
      _log('handleReminderFired: scheduling follow-up for item=${item.id}');
      await NotificationService().scheduleReminder(
        id: finalItem.notificationId,
        title: 'Remember: ${finalItem.title}',
        body: finalItem.description.isNotEmpty
            ? finalItem.description
            : 'Time to revisit this thought.',
        scheduledDate: nextDate,
        payload: finalItem.id,
      );
    } else {
      _log('handleReminderFired: no follow-up schedule for item=${item.id}');
    }
  }
}
