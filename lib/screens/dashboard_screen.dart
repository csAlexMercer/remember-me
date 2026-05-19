import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/remember_item.dart';
import '../services/firebase_service.dart';
import 'capture_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<RememberItem> _filterItems(List<RememberItem> items) {
    if (_searchQuery.isEmpty) return items;
    final query = _searchQuery.toLowerCase();
    return items.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    final theme = Theme.of(context);
    final user = firebaseService.currentUser;
    
    String firstName = 'User';
    if (user != null && user.displayName != null && user.displayName!.isNotEmpty) {
      firstName = user.displayName!.trim().split(' ').first;
    } else if (firebaseService.isAnonymous) {
      firstName = 'Guest';
    }

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                  hintText: 'Search thoughts...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : Text('Hello, $firstName!', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
                _isSearching = !_isSearching;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.secondary,
          tabs: const [
            Tab(text: 'Now (Active)'),
            Tab(text: 'Zzz (Asleep)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildItemList(firebaseService.getActiveItems(), isActive: true),
          _buildItemList(firebaseService.getAsleepItems(), isActive: false),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CaptureScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildItemList(Stream<List<RememberItem>> stream, {required bool isActive}) {
    return StreamBuilder<List<RememberItem>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final allItems = snapshot.data ?? [];
        final items = _filterItems(allItems);

        if (allItems.isEmpty) {
          return Center(
            child: Text(
              isActive ? 'No active thoughts. Clear mind!' : 'No asleep thoughts.',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        if (items.isEmpty && _searchQuery.isNotEmpty) {
          return const Center(
            child: Text(
              'No matching thoughts found.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return AnimatedList(
          key: ValueKey('${isActive}_${items.length}'),
          padding: const EdgeInsets.all(16),
          initialItemCount: items.length,
          itemBuilder: (context, index, animation) {
            if (index >= items.length) return const SizedBox.shrink();
            final item = items[index];
            return _buildAnimatedItemCard(item, context, isActive, animation);
          },
        );
      },
    );
  }

  Widget _buildAnimatedItemCard(
    RememberItem item,
    BuildContext context,
    bool isActive,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: _buildItemCard(item, context, isActive),
      ),
    );
  }

  Widget _buildItemCard(RememberItem item, BuildContext context, bool isActive) {
    final theme = Theme.of(context);
    final isHighPriority = item.priority >= 70;
    
    return Dismissible(
      key: Key(item.id),
      background: Container(
        decoration: BoxDecoration(
          color: Colors.green.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: isActive ? Colors.blueGrey : Colors.blue.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              isActive ? 'Sleep' : 'Wake',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Icon(isActive ? Icons.bedtime : Icons.alarm_on, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        final firebaseService = Provider.of<FirebaseService>(context, listen: false);
        if (direction == DismissDirection.startToEnd) {
          await firebaseService.deleteItem(item.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Item completed and removed')),
            );
          }
          return true;
        } else {
          await firebaseService.toggleSleepStatus(item);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(isActive ? 'Item put to sleep 💤' : 'Item woken up ⏰')),
            );
          }
          return false; // Don't remove — it will naturally move to the other tab
        }
      },
      child: Card(
        elevation: isHighPriority && isActive ? 4 : 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isHighPriority && isActive
              ? BorderSide(color: theme.colorScheme.secondary, width: 2)
              : BorderSide.none,
        ),
        color: isActive ? theme.cardColor : theme.disabledColor.withOpacity(0.1),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: isActive ? theme.textTheme.bodyLarge?.color : Colors.grey,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (isActive && item.isHighPriority && item.nextScheduledReminder != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active, size: 14, color: theme.colorScheme.secondary),
                      const SizedBox(width: 4),
                      Text(
                        'Reminder #${item.reminderCount + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sleep/Wake toggle button — one-tap action from the list
              IconButton(
                icon: Icon(
                  isActive ? Icons.bedtime_outlined : Icons.alarm_on,
                  color: isActive ? Colors.blueGrey : Colors.blue,
                ),
                tooltip: isActive ? 'Put to sleep' : 'Wake up',
                onPressed: () async {
                  final firebaseService = Provider.of<FirebaseService>(context, listen: false);
                  await firebaseService.toggleSleepStatus(item);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isActive ? 'Item put to sleep 💤' : 'Item woken up ⏰'),
                      ),
                    );
                  }
                },
              ),
              // Priority indicator
              SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: item.priority / 100,
                      backgroundColor: Colors.grey.shade300,
                      color: _getPriorityColor(item.priority),
                      strokeWidth: 3,
                    ),
                    Text(
                      '${item.priority}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(int priority) {
    if (priority >= 80) return Colors.redAccent;
    if (priority >= 50) return Colors.orangeAccent;
    return Colors.greenAccent;
  }
}
