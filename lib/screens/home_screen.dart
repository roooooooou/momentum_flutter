import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../providers/events_provider.dart';
import '../models/event_model.dart';
import '../widgets/event_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSyncing = false;
  List<EventModel> _cached = const [];

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

  Future<void> _handleAction(EventModel e, TaskAction action) async {
    final uid = context.read<AuthService>().currentUser!.uid;
    switch (action) {
      case TaskAction.start:
        await CalendarService.instance.startEvent(uid, e);
        break;
      case TaskAction.stop:
        await CalendarService.instance.stopEvent(uid, e);
        break;
      case TaskAction.complete:
        await CalendarService.instance.completeEvent(uid, e);
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(context));
  }

  @override
  Widget build(BuildContext context) {
    final stream = context.watch<EventsProvider>().stream;
    final size = MediaQuery.of(context).size;
    final responsiveText = MediaQuery.of(context).textScaleFactor;

    // Calculate responsive padding based on screen width
    final horizontalPadding = size.width * 0.05; // 5% of screen width
    final verticalPadding = size.height * 0.02; // 2% of screen height

    // Calculate responsive sizes
    final iconSize = size.width * 0.05 > 24 ? 24.0 : size.width * 0.05;
    final titleFontSize = (28 * responsiveText).clamp(22.0, 36.0);
    final buttonHeight = size.height * 0.06; // 6% of screen height

    return Scaffold(
      backgroundColor:
          const Color.fromARGB(255, 255, 250, 243), // Light cream background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: size.height * 0.07, // 7% of screen height
        leadingWidth: 0,
        title: Row(
          children: [
            Icon(Icons.diamond_outlined,
                color: Colors.deepPurple, size: iconSize),
            SizedBox(width: size.width * 0.02),
            Text("home page",
                style: TextStyle(
                    fontSize: (16 * responsiveText).clamp(14.0, 20.0),
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // Responsive spacing based on available height
          final verticalSpacing = constraints.maxHeight * 0.02;
          final listViewSpacing = constraints.maxHeight * 0.015;
          final listPadding = EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          );

          return Column(
            children: [
              SizedBox(height: verticalSpacing),
              Text("Today's Tasks",
                  style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3A4A46))),
              SizedBox(height: verticalSpacing),
              Expanded(
                child: stream == null
                    ? const Center(child: CircularProgressIndicator())
                    : StreamBuilder<List<EventModel>>(
                        stream: stream,
                        builder: (_, snap) {
                          if (snap.hasData && snap.data!.isNotEmpty) {
                            _cached = snap.data!;
                          }
                          final list = _cached;
                          if (list.isEmpty) {
                            return const Center(child: Text('No tasks today.'));
                          }

                          return ListView.separated(
                            padding: listPadding,
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(height: listViewSpacing),
                            itemBuilder: (_, i) => EventCard(
                              event: list[i],
                              onAction: (a) => _handleAction(list[i], a),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                width: size.width * 0.45, // 45% of screen width
                height: buttonHeight,
                margin: EdgeInsets.only(
                  bottom: size.height * 0.03,
                  top: size.height * 0.01,
                ),
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: navigate to Daily Report
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD7DFE0), // Light grey-blue
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(size.width * 0.06),
                    ),
                  ),
                  child: Text('Daily Report',
                      style: TextStyle(
                          fontSize: (16 * responsiveText).clamp(14.0, 20.0),
                          fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          );
        }),
      ),

      // Sync button in bottom-right corner
      floatingActionButton: SizedBox(
        width: size.width * 0.14, // Responsive size based on screen width
        height: size.width * 0.14,
        child: FloatingActionButton(
          onPressed: () => _sync(context),
          backgroundColor: const Color(0xFF98E5EE), // Light cyan
          elevation: 2,
          child: _isSyncing
              ? SizedBox(
                  width: size.width * 0.06,
                  height: size.width * 0.06,
                  child: const CircularProgressIndicator(color: Colors.black54))
              : Icon(Icons.sync,
                  color: Colors.black54, size: size.width * 0.07),
        ),
      ),
    );
  }
}
