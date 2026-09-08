import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../services/app_behavior_settings_service.dart';
import '../reader/reader_background_settings.dart';
import '../reader/widgets/reader_background_surface.dart';
import 'app_font_settings.dart';

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
  required AppFontSettings initialFontSettings,
  required Future<AppFontSettings?> Function() onImportFont,
  required Future<AppFontSettings> Function() onUseSystemFont,
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
      initialFontSettings: initialFontSettings,
      onImportFont: onImportFont,
      onUseSystemFont: onUseSystemFont,
    ),
  );
}

class _ReaderBackgroundSheet extends StatefulWidget {
  const _ReaderBackgroundSheet({
    required this.initialSettings,
    required this.onChanged,
    required this.onImportImage,
    required this.onClearImage,
    required this.initialFontSettings,
    required this.onImportFont,
    required this.onUseSystemFont,
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
  final AppFontSettings initialFontSettings;
  final Future<AppFontSettings?> Function() onImportFont;
  final Future<AppFontSettings> Function() onUseSystemFont;

  @override
  State<_ReaderBackgroundSheet> createState() => _ReaderBackgroundSheetState();
}

class _ReaderBackgroundSheetState extends State<_ReaderBackgroundSheet> {
  late ReaderBackgroundSettings _settings = widget.initialSettings;
  late AppFontSettings _fontSettings = widget.initialFontSettings;
  var _isImportingImage = false;
  var _isChangingFont = false;

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

  Future<void> _openFontSettings() async {
    if (_isChangingFont) return;
    final action = await showModalBottomSheet<_FontAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  '字体设置',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: Icon(
                  _fontSettings.usesCustomFont
                      ? Icons.circle_outlined
                      : Icons.check_circle,
                ),
                title: const Text('使用系统字体'),
                subtitle: const Text('使用当前平台的默认界面字体'),
                onTap: () => Navigator.of(context).pop(_FontAction.system),
              ),
              ListTile(
                leading: Icon(
                  _fontSettings.usesCustomFont
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: const Text('导入字体'),
                subtitle: const Text('选择 TTF 或 OTF 字体文件'),
                onTap: () => Navigator.of(context).pop(_FontAction.import),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    setState(() => _isChangingFont = true);
    try {
      final next = switch (action) {
        _FontAction.system => await widget.onUseSystemFont(),
        _FontAction.import => await widget.onImportFont(),
      };
      if (!mounted || next == null) return;
      setState(() => _fontSettings = next);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('字体设置失败：$error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _isChangingFont = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SizedBox(
        // 设置面板固定占屏高 70%，内容可上下滚动。
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '外观设置',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '可以设置阅读背景和应用字体。',
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
                                const SizedBox(height: 4),
                                Text(
                                  '纯色模式自适应日夜间。',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
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
              const SizedBox(height: 24),
              Text(
                '字体',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Material(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: const Icon(Icons.font_download_outlined),
                  title: const Text('字体设置'),
                  subtitle: Text(
                    _fontSettings.usesCustomFont
                        ? (_fontSettings.displayName ?? '自定义字体')
                        : '使用系统字体',
                  ),
                  trailing: _isChangingFont
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _isChangingFont ? null : _openFontSettings,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '显示设置',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Material(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: showPageTurnButtonsSetting,
                      builder: (context, enabled, _) {
                        return SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          secondary: const Icon(Icons.unfold_more_rounded),
                          title: const Text('显示翻页按钮'),
                          subtitle: const Text('滚动时在阅读区右侧显示上下翻页箭头'),
                          value: enabled,
                          onChanged: saveShowPageTurnButtonsSetting,
                        );
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: showUpdateNotificationSetting,
                      builder: (context, show, _) {
                        return SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          secondary: const Icon(Icons.system_update_alt_rounded),
                          title: const Text('显示更新通知'),
                          subtitle: const Text('发现新版本时在侧边栏显示通知块'),
                          value: show,
                          onChanged: saveShowUpdateNotificationSetting,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '字号与行距',
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: readerFontScaleSetting,
                        builder: (context, scale, _) {
                          return _PercentSliderRow(
                            label: '字号',
                            valueText: '${(scale * 100).round()}%',
                            value: scale,
                            min: AppBehaviorSettings.minReaderFontScale,
                            max: AppBehaviorSettings.maxReaderFontScale,
                            divisions: 16,
                            onChanged: saveReaderFontScaleSetting,
                            sliderLeading: Text(
                              'A',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            sliderTrailing: Text(
                              'A',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: readerLineHeightSetting,
                        builder: (context, lineHeight, _) {
                          return _PercentSliderRow(
                            label: '行距',
                            valueText: '${lineHeight.toStringAsFixed(2)} 倍',
                            value: lineHeight,
                            min: AppBehaviorSettings.minReaderLineHeight,
                            max: AppBehaviorSettings.maxReaderLineHeight,
                            divisions: 12,
                            onChanged: saveReaderLineHeightSetting,
                            sliderLeading: Icon(
                              Icons.density_small_rounded,
                              size: 15,
                              color: cs.onSurfaceVariant,
                            ),
                            sliderTrailing: Icon(
                              Icons.density_large_rounded,
                              size: 19,
                              color: cs.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: Listenable.merge([
                  readerFontScaleSetting,
                  readerLineHeightSetting,
                ]),
                builder: (context, _) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '预览',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          for (final paragraph in _previewParagraphs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                paragraph,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize:
                                          15 * readerFontScaleSetting.value,
                                      height: readerLineHeightSetting.value,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _previewParagraphs = <String>[
  '她关掉台灯，房间里只剩下窗外透进来的一线光。',
  '那些看似平凡的日子，往往在回忆里才显出分量。',
  '阅读的意义，或许就是在别人的故事里，遇见自己的答案。',
];

class _PercentSliderRow extends StatelessWidget {
  const _PercentSliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.sliderLeading,
    this.sliderTrailing,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  /// 滑杆两端的小/大示意图形（如小 A / 大 A）。
  final Widget? sliderLeading;
  final Widget? sliderTrailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  valueText,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            ?sliderLeading,
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  trackShape: const RoundedRectSliderTrackShape(),
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: cs.surfaceContainerHighest,
                  activeTickMarkColor: Colors.transparent,
                  inactiveTickMarkColor: Colors.transparent,
                  thumbColor: cs.primary,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                    elevation: 1,
                    pressedElevation: 3,
                  ),
                  overlayColor: cs.primary.withValues(alpha: 0.12),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ),
            ?sliderTrailing,
          ],
        ),
      ],
    );
  }
}

enum _FontAction { system, import }

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
    final brightness = Theme.of(context).brightness;
    final displayColor = palette.colorFor(brightness);
    final isDark = displayColor.computeLuminance() < 0.4;
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        width: 82,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: displayColor,
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
              palette.labelFor(brightness),
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
