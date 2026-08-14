import 'package:flutter/material.dart';

class BlockingLoader extends StatelessWidget {
  const BlockingLoader({super.key, this.label, this.progress});

  /// Operation label; defaults to a generic "处理中…".
  final String? label;

  /// Determinate progress (0..1). When null an indeterminate spinner is
  /// shown instead.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: progress == null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(label ?? '处理中…'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 240,
                      child: LinearProgressIndicator(value: progress),
                    ),
                    const SizedBox(height: 10),
                    Text(label ?? '处理中…'),
                    const SizedBox(height: 2),
                    Text(
                      '${(progress * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
