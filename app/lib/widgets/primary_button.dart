// app/lib/widgets/primary_button.dart
import 'package:flutter/material.dart';

import '../core/theme/sorted_shape.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: SortedShape.primaryButtonHeight,
      child: FilledButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: SortedShape.iconSize), const SizedBox(width: 8)],
            Text(label),
          ],
        ),
      ),
    );
  }
}
