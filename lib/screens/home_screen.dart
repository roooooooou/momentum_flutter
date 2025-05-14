import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../providers/events_provider.dart';
import '../models/event_model.dart';
import '../widgets/event_item.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSyncing = false;
  List<EventModel> _cachedEvents = const [];

  Future<void> _sync(BuildContext context) async {
    setState(() => _isSyncing = true);
    final uid = context.read<AuthService>().currentUser!.uid;

    try {
      await CalendarService.instance.syncToday(uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // 首次進入就同步
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(context));
  }

  @override
  Widget build(BuildContext context) {
    final eventsStream = context.watch<EventsProvider>().stream;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Events"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => _sync(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1 主要內容：ListView or 快取
          eventsStream == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<EventModel>>(
                  stream: eventsStream,
                  builder: (ctx, snap) {
                    // 更新快取（只有有資料才存）
                    if (snap.hasData && snap.data!.isNotEmpty) {
                      _cachedEvents = snap.data!;
                    }

                    // 用快取決定要顯示什麼
                    final showing = _cachedEvents;
                    if (showing.isEmpty) {
                      return const Center(child: Text('No events today.'));
                    }

                    return ListView.builder(
                      itemCount: showing.length,
                      itemBuilder: (ctx, i) => EventItem(
                        event: showing[i],
                        onToggle: (_) async {
                          final uid =
                              context.read<AuthService>().currentUser!.uid;
                          await CalendarService.instance
                              .toggleEventDone(uid, showing[i]);
                        },
                      ),
                    );
                  },
                ),

          // 2 轉圈圈 overlay：只在同步中顯示
          if (_isSyncing)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
