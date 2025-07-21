import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/event_model.dart';
import '../models/enums.dart';

/// 事件生命周期调试组件
/// 用于显示事件的删除/移动历史记录
class EventLifecycleDebugWidget extends StatefulWidget {
  final User user;

  const EventLifecycleDebugWidget({Key? key, required this.user}) : super(key: key);

  @override
  State<EventLifecycleDebugWidget> createState() => _EventLifecycleDebugWidgetState();
}

class _EventLifecycleDebugWidgetState extends State<EventLifecycleDebugWidget> {
  List<EventModel> _archivedEvents = [];
  Map<EventLifecycleStatus, int> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取最近7天的归档事件
      final archivedEvents = await ExperimentEventHelper.getArchivedEvents(
        uid: widget.user.uid,
        limit: 20,
      );

      // 获取生命周期统计
      final stats = await ExperimentEventHelper.getLifecycleStats(
        uid: widget.user.uid,
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        endDate: DateTime.now(),
      );

      setState(() {
        _archivedEvents = archivedEvents;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载数据失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件生命周期调试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsSection(),
                  const SizedBox(height: 24),
                  _buildArchivedEventsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '生命周期统计（最近30天）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._stats.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key.displayName),
                  Chip(
                    label: Text('${entry.value}'),
                    backgroundColor: _getStatusColor(entry.key).withOpacity(0.2),
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildArchivedEventsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '最近归档的事件',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_archivedEvents.isEmpty)
              const Text('暂无归档事件')
            else
              ..._archivedEvents.map((event) => _buildEventTile(event)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTile(EventModel event) {
    final status = event.lifecycleStatus;
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getStatusColor(status),
        child: Icon(
          _getStatusIcon(status),
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Text(event.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('状态: ${status.displayName}'),
          if (event.archivedAt != null)
            Text('归档时间: ${_formatDateTime(event.archivedAt!)}'),
          if (event.movedFromStartTime != null)
            Text('原时间: ${_formatDateTime(event.movedFromStartTime!)}'),
          if (event.previousEventId != null)
            Text('关联事件: ${event.previousEventId}'),
        ],
      ),
      trailing: event.previousEventId != null || event.movedFromStartTime != null
          ? IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => _showEventHistory(event),
            )
          : null,
    );
  }

  Color _getStatusColor(EventLifecycleStatus status) {
    switch (status) {
      case EventLifecycleStatus.active:
        return Colors.green;
      case EventLifecycleStatus.deleted:
        return Colors.red;
      case EventLifecycleStatus.moved:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(EventLifecycleStatus status) {
    switch (status) {
      case EventLifecycleStatus.active:
        return Icons.check_circle;
      case EventLifecycleStatus.deleted:
        return Icons.delete;
      case EventLifecycleStatus.moved:
        return Icons.move_to_inbox;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showEventHistory(EventModel event) async {
    try {
      final history = await ExperimentEventHelper.getEventHistory(
        uid: widget.user.uid,
        eventId: event.id,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('事件历史: ${event.title}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: history.length,
              itemBuilder: (context, index) {
                final historyEvent = history[index];
                final status = historyEvent.lifecycleStatus;
                
                return ListTile(
                  leading: Icon(
                    _getStatusIcon(status),
                    color: _getStatusColor(status),
                  ),
                  title: Text(historyEvent.title),
                  subtitle: Text(
                    '${status.displayName}\n'
                    '时间: ${_formatDateTime(historyEvent.scheduledStartTime)}',
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取事件历史失败: $e')),
      );
    }
  }
} 