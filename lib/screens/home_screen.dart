import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../providers/events_provider.dart';
import '../models/event_model.dart';
import '../widgets/event_item.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final eventsProvider = Provider.of<EventsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Events"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync Calendar',
            onPressed: () async {
              // Ensure CalendarService was initialised
              final account = auth.googleAccount;
              final uid = auth.currentUser?.uid;
              if (account == null || uid == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not signed in')));
                return;
              }
              try {
                // make sure init is done (no-op if already)
                await CalendarService.instance.init(account);
                await CalendarService.instance.syncToday(uid);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Calendar synced')));
              } catch (e) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
              }
            },
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: auth.signOut),
        ],
      ),
      body: eventsProvider.stream == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<EventModel>>(
              stream: eventsProvider.stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.isEmpty) {
                  return const Center(child: Text('No events today.'));
                }
                final events = snap.data!;
                return ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (_, i) => EventItem(
                    event: events[i],
                    onToggle: (_) async {
                      final uid = auth.currentUser!.uid;
                      await CalendarService.instance
                          .toggleEventDone(uid, events[i]);
                    },
                  ),
                );
              },
            ),
    );
  }
}
