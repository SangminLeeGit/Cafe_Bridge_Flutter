class ApkDownloadCancellationToken {
  bool _isCancelled = false;
  void Function()? _cancelActiveDownload;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _cancelActiveDownload?.call();
  }

  void attach(void Function() cancelActiveDownload) {
    if (_isCancelled) {
      cancelActiveDownload();
      return;
    }
    _cancelActiveDownload = cancelActiveDownload;
  }

  void detach() {
    _cancelActiveDownload = null;
  }
}

enum AppInstallerStatus {
  installerOpened,
  permissionRequired,
}

class AppInstallerResult {
  final AppInstallerStatus status;
  final String message;
  final bool canRetry;

  const AppInstallerResult({
    required this.status,
    required this.message,
    required this.canRetry,
  });

  factory AppInstallerResult.fromChannel(Map<Object?, Object?> value) {
    final rawStatus = value['status'];
    final status = switch (rawStatus) {
      'installerOpened' => AppInstallerStatus.installerOpened,
      'permissionRequired' => AppInstallerStatus.permissionRequired,
      _ => throw FormatException('알 수 없는 APK 설치 상태입니다: $rawStatus'),
    };
    final message = value['message'];
    final canRetry = value['canRetry'];
    if (message is! String || canRetry is! bool) {
      throw const FormatException('APK 설치 상태 응답 형식이 올바르지 않습니다.');
    }
    return AppInstallerResult(
      status: status,
      message: message,
      canRetry: canRetry,
    );
  }
}
