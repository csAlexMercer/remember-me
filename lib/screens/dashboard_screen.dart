import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/remember_item.dart';
import '../services/firebase_service.dart';
import 'capture_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remember Me', style: TextStyle(fontWeight: FontWeight.bold)),
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
          return Center(child: Text('Error: \${snapshot.error}'));
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return Center(
            child: Text(
              isActive ? 'No active thoughts. Clear mind!' : 'No asleep thoughts.',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _buildItemCard(item, context, isActive);
          },
        );
      },
    );
  }

  Widget _buildItemCard(RememberItem item, BuildContext context, bool isActive) {
    final theme = Theme.of(context);
    final isHighPriority = item.priority >= 70;
    
    return Dismissible(
      key: Key(item.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: isActive ? Colors.grey : Colors.blue,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(isActive ? Icons.snooze : Icons.alarm_on, color: Colors.white),
      ),
      onDismissed: (direction) async {
        final firebaseService = Provider.of<FirebaseService>(context, listen: false);
        if (direction == DismissDirection.startToEnd) {
          // Complete / Delete
          await firebaseService.deleteItem(item.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item completed and removed')),
          );
        } else {
          // Toggle sleep
          await firebaseService.toggleSleepStatus(item);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isActive ? 'Item put to sleep' : 'Item woken up')),
          );
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
          contentPadding: const EdgeInsets.all(16),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: isActive ? theme.textTheme.bodyLarge?.color : Colors.grey,
            ),
          ),
          subtitle: item.description.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : null,
          trailing: CircularProgressIndicator(
            value: item.priority / 100,
            backgroundColor: Colors.grey.shade300,
            color: _getPriorityColor(item.priority),
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
