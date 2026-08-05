import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class AppUpdateBanner extends StatelessWidget {
  final bool dense;

  const AppUpdateBanner({
    super.key,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final updateInfo = appState.updateInfo;
    if (updateInfo == null || !updateInfo.updateAvailable) {
      return const SizedBox.shrink();
    }

    final progress = appState.updateDownloadProgress;
    final latestLabel = updateInfo.displayLabel;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dense ? 12 : 14),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(dense ? 0 : 18),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 520;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '권장 업데이트 $latestLabel 이(가) 준비되었습니다.',
                style: const TextStyle(
                  color: AppColors.warningForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (updateInfo.releaseNotes.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  updateInfo.releaseNotes.trim(),
                  style: const TextStyle(
                    color: AppColors.warningForeground,
                    height: 1.35,
                  ),
                ),
              ],
              if (appState.updateStatusMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  appState.updateStatusMessage,
                  style: const TextStyle(
                    color: AppColors.warningStrong,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
              if (appState.isUpdateActionInProgress) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.warningBorder,
                  color: AppColors.warningAction,
                ),
              ],
            ],
          );

          final action = _buildAction(context, appState);

          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: action),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildAction(BuildContext context, AppState appState) {
    final hasDownloadedPackage = appState.canInstallDownloadedUpdate;
    final canTrigger = hasDownloadedPackage || appState.canStartAppUpdate;
    final progress = appState.updateDownloadProgress;

    final installButton = FilledButton.tonalIcon(
      onPressed: !canTrigger || appState.isUpdateActionInProgress
          ? null
          : () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              try {
                if (hasDownloadedPackage) {
                  await context.read<AppState>().installDownloadedAppUpdate();
                } else {
                  await context.read<AppState>().downloadAndInstallAppUpdate();
                }
                if (!context.mounted || messenger == null) {
                  return;
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(context.read<AppState>().updateStatusMessage),
                  ),
                );
              } catch (error) {
                if (!context.mounted || messenger == null) {
                  return;
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(context.read<AppState>().updateStatusMessage),
                  ),
                );
              }
            },
      icon: Icon(
        hasDownloadedPackage
            ? Icons.install_mobile_outlined
            : Icons.download_for_offline_outlined,
      ),
      label: Text(
        appState.isUpdateActionInProgress
            ? _progressLabel(progress)
            : hasDownloadedPackage
                ? '설치 다시 열기'
                : '다운로드 및 설치',
      ),
    );
    if (!appState.isUpdateActionInProgress) {
      return installButton;
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        installButton,
        OutlinedButton.icon(
          onPressed: appState.cancelAppUpdateDownload,
          icon: const Icon(Icons.close),
          label: const Text('취소'),
        ),
      ],
    );
  }

  String _progressLabel(double? progress) {
    if (progress == null) {
      return '다운로드 중...';
    }
    return '다운로드 ${(progress * 100).clamp(0, 100).round()}%';
  }
}
