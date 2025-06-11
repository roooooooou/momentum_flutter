import 'package:flutter/material.dart';

class OptionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const OptionButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
