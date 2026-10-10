import 'package:flutter/material.dart';

import '../../core/theme/sorted_shape.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SortedShape.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sorted', style: text.headlineLarge),
            const SizedBox(height: 8),
            Text('From DM to paid. Sorted.', style: text.bodyLarge),
          ],
        ),
      ),
    );
  }
}
