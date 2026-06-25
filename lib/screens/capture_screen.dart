import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/remember_item.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({Key? key}) : super(key: key);

  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  double _priority = 60.0;
  bool _isSaving = false;

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[CaptureScreen] $message');
    }
  }

  Future<void> _saveItem() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    _log(
      'saveItem: start title="${_titleController.text.trim()}" priority=${_priority.toInt()}',
    );

    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    final userId = firebaseService.currentUser?.uid ?? '';

    if (userId.isEmpty) {
      setState(() => _isSaving = false);
      return;
    }

    final now = DateTime.now();

    // Build the item (without ID — Firestore will generate it)
    final item = RememberItem(
      id: '',
      userId: userId,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      priority: _priority.toInt(),
      createdAt: now,
      reminderCount: 0,
    );

    // Calculate initial scheduled date using the model's built-in logic
    final scheduledDate = item.calculateNextReminderDate();
    _log(
      'saveItem: calculated scheduledDate=${scheduledDate?.toIso8601String()}',
    );

    try {
      // Save to Firestore first to get the document ID
      final docId = await firebaseService.addItem(
        item.copyWith(nextScheduledReminder: scheduledDate),
      );
      _log('saveItem: Firestore add complete docId=$docId');

      // Schedule notification using the stable Firestore doc ID
      if (docId != null && scheduledDate != null) {
        final notifId = docId.hashCode.abs();
        _log(
          'saveItem: scheduling notification notifId=$notifId payload=$docId',
        );
        await NotificationService().scheduleReminder(
          id: notifId,
          title: 'Remember: ${item.title}',
          body: item.description.isNotEmpty
              ? item.description
              : 'High priority item reminder.',
          scheduledDate: scheduledDate,
          payload: docId,
        );
      } else {
        _log(
          'saveItem: skipped scheduling docId=$docId scheduledDate=${scheduledDate?.toIso8601String()}',
        );
      }

      if (mounted) {
        _titleController.clear();
        _descController.clear();
        setState(() {
          _priority = 60.0;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item saved!')));
        Navigator.pop(context);
      }
      _log('saveItem: complete');
    } catch (e) {
      _log('saveItem: error $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
      _log('saveItem: finalizing');
    }
  }

  String _getPriorityLabel(double priority) {
    if (priority >= 90) return 'Urgent — notify in 8h';
    if (priority >= 80) return 'High — notify in 12h';
    if (priority >= 70) return 'Medium — notify in 24h';
    if (priority >= 60) return 'Low — notify in 48h';
    return 'Low';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Capture Your Thought',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: "What's on your mind?",
                  border: InputBorder.none,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Is there more to it?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Priority: ${_priority.toInt()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getPriorityLabel(_priority),
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 8,
                  activeTrackColor: theme.colorScheme.secondary,
                  inactiveTrackColor: theme.colorScheme.secondary.withValues(
                    alpha: 0.2,
                  ),
                  thumbColor: theme.colorScheme.primary,
                  overlayColor: theme.colorScheme.primary.withValues(
                    alpha: 0.2,
                  ),
                ),
                child: Slider(
                  value: _priority,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: (value) {
                    if (_priority.toInt() != value.toInt()) {
                      HapticFeedback.selectionClick();
                    }
                    setState(() {
                      _priority = value;
                    });
                  },
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveItem,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Save Thought',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
