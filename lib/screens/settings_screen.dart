import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/theme_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _quietEnabled = false;
  int _quietStartHour = 22;
  int _quietEndHour = 7;
  bool _isLoading = true;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await NotificationService().getQuietHoursSettings();
    if (mounted) {
      setState(() {
        _quietEnabled = settings['enabled'] as bool;
        _quietStartHour = settings['startHour'] as int;
        _quietEndHour = settings['endHour'] as int;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveQuietHours() async {
    await NotificationService().setQuietHoursSettings(
      enabled: _quietEnabled,
      startHour: _quietStartHour,
      endHour: _quietEndHour,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _pickHour(
    String label,
    int currentHour,
    ValueChanged<int> onPicked,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentHour, minute: 0),
      helpText: label,
    );
    if (picked != null) {
      onPicked(picked.hour);
    }
  }

  String _formatHour(int hour) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:00 $period';
  }

  Future<void> _showDeleteAccountDialog() async {
    if (_isDeletingAccount) return;

    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );

    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Delete My Account'),
          content: const Text(
            'Deleting your account will remove all your thoughts and ideas forever.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    setState(() {
      _isDeletingAccount = true;
    });

    try {
      await firebaseService.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAccount = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = firebaseService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Account Section ──────────────────────────
                Text(
                  'ACCOUNT',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: theme.colorScheme.primary
                                  .withOpacity(0.2),
                              backgroundImage: user?.photoURL != null
                                  ? NetworkImage(user!.photoURL!)
                                  : null,
                              child: user?.photoURL == null
                                  ? Icon(
                                      Icons.person,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user?.displayName != null &&
                                            user!.displayName!.isNotEmpty
                                        ? user.displayName!
                                              .trim()
                                              .split(' ')
                                              .first
                                        : 'User',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user?.email ?? '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await firebaseService.signOut();
                              if (mounted) {
                                Navigator.of(
                                  context,
                                ).popUntil((route) => route.isFirst);
                              }
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text('Sign Out'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Appearance Section ────────────────────────────
                Text(
                  'APPEARANCE',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Theme Mode'),
                        trailing: DropdownButton<ThemeMode>(
                          value: themeProvider.themeMode,
                          underline: const SizedBox(),
                          onChanged: (ThemeMode? newMode) {
                            if (newMode != null) {
                              themeProvider.updateThemeMode(newMode);
                            }
                          },
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Theme Color'),
                        trailing: GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                Color pickerColor = themeProvider.primaryColor;
                                return AlertDialog(
                                  title: const Text('Pick a color!'),
                                  content: SingleChildScrollView(
                                    child: ColorPicker(
                                      pickerColor: pickerColor,
                                      onColorChanged: (Color color) {
                                        pickerColor = color;
                                      },
                                      pickerAreaHeightPercent: 0.8,
                                    ),
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                      child: const Text('Cancel'),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                    TextButton(
                                      child: const Text('Save'),
                                      onPressed: () {
                                        themeProvider.updatePrimaryColor(
                                          pickerColor,
                                        );
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: themeProvider.primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Notification Settings ────────────────────
                Text(
                  'NOTIFICATIONS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Quiet Hours'),
                          subtitle: const Text(
                            'Suppress notifications during sleep',
                          ),
                          value: _quietEnabled,
                          activeColor: theme.colorScheme.secondary,
                          onChanged: (value) {
                            setState(() => _quietEnabled = value);
                            _saveQuietHours();
                          },
                        ),
                        if (_quietEnabled) ...[
                          const Divider(height: 1),
                          ListTile(
                            title: const Text('Start'),
                            trailing: TextButton(
                              onPressed: () => _pickHour(
                                'Quiet hours start',
                                _quietStartHour,
                                (hour) {
                                  setState(() => _quietStartHour = hour);
                                  _saveQuietHours();
                                },
                              ),
                              child: Text(
                                _formatHour(_quietStartHour),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text('End'),
                            trailing: TextButton(
                              onPressed: () => _pickHour(
                                'Quiet hours end',
                                _quietEndHour,
                                (hour) {
                                  setState(() => _quietEndHour = hour);
                                  _saveQuietHours();
                                },
                              ),
                              child: Text(
                                _formatHour(_quietEndHour),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── About Section ────────────────────────────
                Text(
                  'ABOUT',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: const [
                      ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Version'),
                        trailing: Text('1.0.0'),
                      ),
                      ListTile(
                        leading: Icon(Icons.favorite_outline),
                        title: Text('Designed for the ADHD brain'),
                        subtitle: Text(
                          'Active retrieval, not a data graveyard',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                Center(
                  child: SizedBox(
                    width: 220,
                    child: OutlinedButton.icon(
                      onPressed: _isDeletingAccount
                          ? null
                          : _showDeleteAccountDialog,
                      icon: _isDeletingAccount
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_forever),
                      label: Text(
                        _isDeletingAccount
                            ? 'Deleting...'
                            : 'Delete My Account',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
