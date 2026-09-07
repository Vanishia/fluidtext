import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_settings.dart';
import '../../services/app_logger.dart';
import '../../services/update_check_service.dart';

/// 侧边栏里的更新设置开关：控制发现新版本时是否显示 [UpdateNoticeBlock]。
class UpdateNotificationSwitch extends StatelessWidget {
  const UpdateNotificationSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showUpdateNotificationSetting,
      builder: (context, show, _) {
        return SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 2),
          title: const Text('显示更新通知'),
          value: show,
          onChanged: saveShowUpdateNotificationSetting,
        );
      },
    );
  }
}

/// 侧边栏里的新版本通知块：有新版本且开关打开时显示，点击查看更新详情。
class UpdateNoticeBlock extends StatelessWidget {
  const UpdateNoticeBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showUpdateNotificationSetting,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return ValueListenableBuilder<AppUpdateInfo?>(
          valueListenable: UpdateCheckService.instance.availableUpdate,
          builder: (context, update, _) {
            if (update == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _UpdateCard(update: update),
            );
          },
        );
      },
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.update});

  final AppUpdateInfo update;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showUpdateDetailDialog(context, update),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.system_update_alt_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '有新版本 ${update.version}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 更新详情弹窗：显示 release 说明，底部提供下载按钮。
Future<void> showUpdateDetailDialog(
  BuildContext context,
  AppUpdateInfo update,
) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('新版本 ${update.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
          child: SingleChildScrollView(
            child: SelectableText(
              update.notes.isEmpty ? '（该版本没有更新说明）' : update.notes,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () => _downloadUpdate(update),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('下载'),
          ),
        ],
      );
    },
  );
}

Future<void> _downloadUpdate(AppUpdateInfo update) async {
  final url = update.downloadUrl;
  try {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      AppLogger.instance.warning('UpdateCheck', '无法打开下载链接: $url');
    }
  } catch (error, stackTrace) {
    AppLogger.instance.warning(
      'UpdateCheck',
      '打开下载链接失败: $url',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
