import 'package:flutter/material.dart';
import '../models/event_model.dart';

class EventItem extends StatelessWidget {
  final EventModel event;
  final void Function(bool?) onToggle;

  const EventItem({super.key, required this.event, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: event.isDone,
      onChanged: onToggle,
      title: Text(event.title,
          style: event.isDone
              ? const TextStyle(
                  decoration: TextDecoration.lineThrough, color: Colors.grey)
              : null),
      subtitle: Text(event.timeRange),
    );
  }
}
