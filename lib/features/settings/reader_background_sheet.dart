import 'dart:async';

import 'package:flutter/material.dart';

import '../reader/reader_background_settings.dart';
import '../reader/widgets/reader_background_surface.dart';

Future<void> showReaderBackgroundSheet(
  BuildContext context, {
  required ReaderBackgroundSettings initialSettings,
  required Future<void> Function(ReaderBackgroundSettings settings) onChanged,
  required Future<ReaderBackgroundSettings?> Function(
    ReaderBackgroundSettings settings,
  )
  onImportImage,
  required Future<ReaderBackgroundSettings> Function(
    ReaderBackgroundSettings settings,
  )
  onClearImage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _ReaderBackgroundSheet(
      initialSettings: initialSettings,
      onChanged: onChanged,
      onImportImage: onImportImage,
      onClearImage: onClearImage,
    ),
  );
}

class _ReaderBackgroundSheet extends StatefulWidget {
  const _ReaderBackgroundSheet({
    required this.initialSettings,
    required this.onChanged,
    required this.onImportImage,
    required this.onClearImage,
  });

  final ReaderBackgroundSettings initialSettings;
  final Future<void> Function(ReaderBackgroundSettings settings) onChanged;
  final Future<ReaderBackgroundSettings?> Function(
    ReaderBackgroundSettings settings,
  )
  onImportImage;
  final Future<ReaderBackgroundSettings> Function(
    ReaderBackgroundSettings settings,
  )
  onClearImage;

  @override
  State<_ReaderBackgroundSheet> createState() => _ReaderBackgroundSheetState();
}

class _ReaderBackgroundSheetState extends State<_ReaderBackgroundSheet> {
  late ReaderBackgroundSettings _settings = widget.initialSettings;
  var _isImportingImage = false;

  void _apply(ReaderBackgroundSettings next) {
    setState(() {
      _settings = next;
    });
    unawaited(widget.onChanged(next));
  }

  Future<void> _importImage() async {
    if (_isImportingImage) return;

    setState(() {
      _isImportingImage = true;
    });

    try {
      final next = await widget.onImportImage(_settings);
      if (!mounted || next == null) return;
      setState(() {
        _settings = next;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImportingImage = false;
        });
      }
    }
  }

  Future<void> _clearImage() async {
    if (_isImportingImage) return;

    setState(() {
      _isImportingImage = true;
    });

    try {
      final next = await widget.onClearImage(_settings);
      if (!mounted) return;
      setState(() {
        _settings = next;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImportingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '阅读背景',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '可以使用纯色，或上传一张图片，再叠加固定纹理。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 148,
                width: double.infinity,
                child: ReaderBackgroundSurface(
                  settings: _settings,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '预览卡片',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '背景会立刻应用到阅读页面。',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '自定义图片',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _settings.hasCustomImage
                          ? '当前正在使用自定义图片背景。'
                          : '上传后会覆盖当前预览，切回纯色时仍会保留你选的颜色。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _isImportingImage ? null : _importImage,
                          icon: _isImportingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.image_outlined),
                          label: Text(
                            _settings.hasCustomImage ? '更换图片' : '上传图片',
                          ),
                        ),
                        if (_settings.hasCustomImage) ...[
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _isImportingImage ? null : _clearImage,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('移除图片'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '纯色',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final palette in readerBackgroundPalettes)
                  _PaletteChip(
                    palette: palette,
                    selected:
                        _settings.source == ReaderBackgroundSource.color &&
                        palette.key == _settings.paletteKey,
                    onTap: () => _apply(
                      _settings.copyWith(
                        source: ReaderBackgroundSource.color,
                        paletteKey: palette.key,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '纹理',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final texture in ReaderTexturePreset.values)
                  ChoiceChip(
                    label: Text(texture.label),
                    selected: texture == _settings.texture,
                    onSelected: (_) =>
                        _apply(_settings.copyWith(texture: texture)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ReaderBackgroundPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = palette.color.computeLuminance() < 0.4;
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        width: 82,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: palette.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? cs.primary
                : (isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : cs.outlineVariant.withValues(alpha: 0.62)),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: selected
                    ? cs.primary
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.72)
                          : cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              palette.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
