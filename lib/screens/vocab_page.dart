import 'package:flutter/material.dart';
import '../models/event_model.dart';

class VocabPage extends StatefulWidget {
  final EventModel event;
  
  const VocabPage({
    super.key,
    required this.event,
  });

  @override
  State<VocabPage> createState() => _VocabPageState();
}

class _VocabPageState extends State<VocabPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('词汇学习 - ${widget.event.title}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.book,
              size: 64,
              color: Colors.blue,
            ),
            SizedBox(height: 16),
            Text(
              '词汇学习页面',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '内容开发中...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 