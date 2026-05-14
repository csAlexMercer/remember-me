import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
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

  Future<void> _saveItem() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    final userId = firebaseService.currentUser?.uid ?? '';
    
    if (userId.isEmpty) {
      // Handle not logged in state
      setState(() => _isSaving = false);
      return;
    }

    final now = DateTime.now();
    DateTime? scheduledDate;

    // Calculate initial delay based on priority (Phase 1 logic)
    if (_priority >= 90) {
      scheduledDate = now.add(const Duration(hours: 8));
    } else if (_priority >= 80) {
      scheduledDate = now.add(const Duration(hours: 12));
    } else if (_priority >= 70) {
      scheduledDate = now.add(const Duration(hours: 24));
    }

    final item = RememberItem(
      id: '', // Firestore will auto-generate if we add via collection, but we need ID for notification.
      userId: userId,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      priority: _priority.toInt(),
      createdAt: now,
      nextScheduledReminder: scheduledDate,
    );

    try {
      // Actually, to schedule a notification, we need a numeric ID. 
      // We can use the hashcode of the item's title + timestamp for phase 1.
      final notifId = item.title.hashCode + now.hashCode;

      if (scheduledDate != null) {
        await NotificationService().scheduleReminder(
          id: notifId.abs(),
          title: 'Remember: \${item.title}',
          body: item.description.isNotEmpty ? item.description : 'High priority item reminder.',
          scheduledDate: scheduledDate,
        );
      }

      await firebaseService.addItem(item);

      if (mounted) {
        _titleController.clear();
        _descController.clear();
        setState(() {
          _priority = 60.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: \$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Idea', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
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
                  hintText: 'Optional details...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Priority: \${_priority.toInt()}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 8,
                  activeTrackColor: theme.colorScheme.secondary,
                  inactiveTrackColor: theme.colorScheme.secondary.withOpacity(0.2),
                  thumbColor: theme.colorScheme.primary,
                  overlayColor: theme.colorScheme.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: _priority,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: (value) {
                    setState(() {
                      _priority = value;
                    });
                    // Provide haptic feedback on multiples of 10
                    if (value % 10 == 0) {
                      Vibration.hasVibrator().then((hasVibrator) {
                        if (hasVibrator == true) {
                          Vibration.vibrate(duration: 20);
                        }
                      });
                    }
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
                  : const Text('Save Thought', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
