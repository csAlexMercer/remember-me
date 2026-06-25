import 'dart:ui';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animated_icons/lottiefiles.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:lottie/lottie.dart';
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

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late final AnimationController _flipController;
  late final Stream<List<RememberItem>> _activeItemsStream;
  late final Stream<List<RememberItem>> _asleepItemsStream;
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isCircleExpanded = true;
  bool _startupReminderCheckRan = false;
  bool _isBackFaceVisible = false;
  bool _showShakeHint = false;
  bool _isRefreshingFeaturedItem = false;
  RememberItem? _featuredItem;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _shakeHintTimer;
  DateTime? _lastShakeAt;
  final math.Random _random = math.Random();
  final _searchController = TextEditingController();

  static const Duration _flipDuration = Duration(milliseconds: 420);
  static const Duration _hintDelay = Duration(seconds: 10);
  static const Duration _shakeCooldown = Duration(milliseconds: 900);
  static const double _circleSize = 320;
  static const double _frontFaceSize = 410;
  static const double _featureCardWidth = 420;
  static const double _featureCardHeight = 350;
  static const double _shakeThreshold = 18;

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[DashboardScreen] $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _log('initState: start');
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    _activeItemsStream = firebaseService.getActiveItems();
    _asleepItemsStream = firebaseService.getAsleepItems();
    _tabController = TabController(length: 2, vsync: this);
    _flipController = AnimationController(vsync: this, duration: _flipDuration);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _log('postFrame: starting startup checks');
      _runStartupReminderCheck();
      _loadFeaturedItem();
      _startShakeListener();
    });
  }

  Future<void> _runStartupReminderCheck() async {
    if (!mounted || _startupReminderCheckRan) return;
    _startupReminderCheckRan = true;

    _log('startupReminderCheck: running');

    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    await firebaseService.runStartupReminderCheck();
    _log('startupReminderCheck: complete');
  }

  Future<void> _loadFeaturedItem() async {
    _log('loadFeaturedItem: start');
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    final activeItems = await firebaseService.getActiveItemsOnce();
    _log('loadFeaturedItem: fetched ${activeItems.length} active items');
    if (!mounted) return;

    setState(() {
      _featuredItem = _pickRandomItem(activeItems);
    });

    _log('loadFeaturedItem: selected item=${_featuredItem?.id}');

    if (_isBackFaceVisible && _featuredItem != null) {
      _scheduleShakeHint();
    }
  }

  RememberItem? _pickRandomItem(List<RememberItem> items) {
    if (items.isEmpty) return null;
    if (items.length == 1) return items.first;

    final shuffled = List<RememberItem>.from(items)..shuffle(_random);
    final current = _featuredItem;
    if (current != null && shuffled.first.id == current.id) {
      return shuffled[1];
    }
    return shuffled.first;
  }

  void _startShakeListener() {
    _log('shakeListener: start');
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      if (!mounted || !_isBackFaceVisible || _isRefreshingFeaturedItem) {
        return;
      }

      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      final now = DateTime.now();

      if (_lastShakeAt != null &&
          now.difference(_lastShakeAt!) < _shakeCooldown) {
        return;
      }

      if (magnitude >= _shakeThreshold) {
        _lastShakeAt = now;
        _log('shakeListener: shake detected magnitude=$magnitude');
        HapticFeedback.mediumImpact();
        _refreshFeaturedItem();
      }
    });
  }

  Future<void> _refreshFeaturedItem() async {
    if (_isRefreshingFeaturedItem) return;

    _log('refreshFeaturedItem: start');

    setState(() {
      _isRefreshingFeaturedItem = true;
      _showShakeHint = false;
    });

    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    final activeItems = await firebaseService.getActiveItemsOnce();
    _log('refreshFeaturedItem: fetched ${activeItems.length} active items');
    if (!mounted) return;

    final nextItem = _pickRandomItem(activeItems);
    setState(() {
      _featuredItem = nextItem;
      _isRefreshingFeaturedItem = false;
    });

    _log('refreshFeaturedItem: selected item=${_featuredItem?.id}');

    if (_isBackFaceVisible) {
      _scheduleShakeHint();
    }
  }

  void _scheduleShakeHint() {
    _shakeHintTimer?.cancel();
    _showShakeHint = false;

    _shakeHintTimer = Timer(_hintDelay, () {
      if (!mounted || !_isBackFaceVisible) return;
      setState(() {
        _showShakeHint = true;
      });
    });
  }

  void _cancelShakeHintTimer() {
    _shakeHintTimer?.cancel();
    _shakeHintTimer = null;
    _showShakeHint = false;
  }

  Future<void> _showFeaturedFace() async {
    if (_isBackFaceVisible) return;
    setState(() {
      _isBackFaceVisible = true;
      _showShakeHint = false;
    });
    await _flipController.forward();
    if (mounted) {
      _scheduleShakeHint();
    }
  }

  Future<void> _showAddFace() async {
    if (!_isBackFaceVisible) return;
    _cancelShakeHintTimer();
    setState(() {
      _isBackFaceVisible = false;
    });
    await _flipController.reverse();
  }

  void _toggleFeaturedFace() {
    if (_isBackFaceVisible) {
      _showAddFace();
    } else {
      _showFeaturedFace();
    }
  }

  void _expandCircle() {
    if (_isCircleExpanded) return;
    setState(() {
      _isCircleExpanded = true;
    });
  }

  void _collapseCircle() {
    if (!_isCircleExpanded) return;
    setState(() {
      _isCircleExpanded = false;
      _showShakeHint = false;
    });
    _cancelShakeHintTimer();
  }

  Future<void> _openCaptureScreen() async {
    HapticFeedback.mediumImpact();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CaptureScreen()),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _flipController.dispose();
    _searchController.dispose();
    _accelerometerSubscription?.cancel();
    _shakeHintTimer?.cancel();
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
    if (user != null &&
        user.displayName != null &&
        user.displayName!.isNotEmpty) {
      firstName = user.displayName!.trim().split(' ').first;
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
            : Text(
                'Hello, $firstName!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final circleTop = (constraints.maxHeight - _circleSize) / 2.5;

          return Stack(
            children: [
              IgnorePointer(
                ignoring: _isCircleExpanded,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildItemList(_activeItemsStream, isActive: true),
                    _buildItemList(_asleepItemsStream, isActive: false),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_isCircleExpanded,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _isCircleExpanded ? 1 : 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _collapseCircle,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                top: _isCircleExpanded ? circleTop : 630,
                bottom: _isCircleExpanded ? null : -(_circleSize * 0.8),
                child: SafeArea(
                  top: false,
                  child: Center(child: _buildFeaturedFlipCard(context)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFeaturedFlipCard(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_isCircleExpanded) {
          _expandCircle();
          return;
        }

        if (!_isBackFaceVisible) {
          _openCaptureScreen();
        }
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() >= 120) {
          _toggleFeaturedFace();
        }
      },
      child: AnimatedBuilder(
        animation: _flipController,
        builder: (context, child) {
          final flipValue = _flipController.value;
          return SizedBox(
            width: _featureCardWidth,
            height: _featureCardHeight,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(flipValue * math.pi),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 1 - flipValue.clamp(0.0, 1.0),
                    child: _buildAddFace(theme),
                  ),
                  Opacity(
                    opacity: flipValue.clamp(0.0, 1.0),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(math.pi),
                      child: _buildRandomItemFace(theme),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddFace(ThemeData theme) {
    return Center(
      child: Material(
        color: theme.colorScheme.primary,
        elevation: 18,
        shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: Container(
          width: _frontFaceSize,
          height: _frontFaceSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.mode_rounded, size: 42, color: Colors.white),
              SizedBox(height: 8),
              Text(
                'What\'s on your mind?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRandomItemFace(ThemeData theme) {
    final item = _featuredItem;

    return Stack(
      children: [
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) {
              final fade = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              );
              final scale = Tween<double>(begin: 0.92, end: 1.0).animate(fade);
              return FadeTransition(
                opacity: fade,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: Container(
              key: ValueKey<String>(item?.id ?? 'empty'),
              width: _featureCardWidth * 0.9,
              height: _featureCardHeight * 0.8,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: theme.colorScheme.surface,
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: item == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No active thoughts yet',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Swipe back and add one.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'From your treasury of thoughts',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (item.description.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Center(
                              child: SizedBox(
                                width: 132,
                                height: 132,
                                child: Lottie.asset(
                                  LottieFiles.$9138_open_treasure_icon,
                                  repeat: true,
                                ),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Text(
                              item.description,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 240),
            opacity: _showShakeHint ? 1 : 0,
            child: Text(
              'Shake to refresh',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemList(
    Stream<List<RememberItem>> stream, {
    required bool isActive,
  }) {
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
              isActive
                  ? 'No active thoughts. Clear mind!'
                  : 'No asleep thoughts.',
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 220),
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

  Widget _buildItemCard(
    RememberItem item,
    BuildContext context,
    bool isActive,
  ) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
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
            Text(
              'Complete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isActive ? Icons.bedtime : Icons.alarm_on,
              color: Colors.white,
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        final firebaseService = Provider.of<FirebaseService>(
          context,
          listen: false,
        );
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
              SnackBar(
                content: Text(
                  isActive ? 'Item put to sleep 💤' : 'Item woken up ⏰',
                ),
              ),
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
        color: isActive
            ? theme.cardColor
            : theme.disabledColor.withValues(alpha: 0.1),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: isDarkMode
                  ? Colors.white
                  : isActive
                  ? theme.textTheme.bodyLarge?.color
                  : Colors.black,
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
              if (isActive &&
                  item.isHighPriority &&
                  item.nextScheduledReminder != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active,
                        size: 14,
                        color: theme.colorScheme.secondary,
                      ),
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
                  HapticFeedback.mediumImpact();
                  final firebaseService = Provider.of<FirebaseService>(
                    context,
                    listen: false,
                  );
                  await firebaseService.toggleSleepStatus(item);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isActive ? 'Item put to sleep 💤' : 'Item woken up ⏰',
                        ),
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
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
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
