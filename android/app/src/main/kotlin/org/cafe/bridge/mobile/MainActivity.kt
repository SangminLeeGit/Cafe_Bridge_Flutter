package org.cafe.bridge.mobile

import android.content.ClipData
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "org.cafe.bridge.mobile/app_update"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val STATUS_INSTALLER_OPENED = "installerOpened"
        private const val STATUS_PERMISSION_REQUIRED = "permissionRequired"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "verifyAndInstallApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val filePath = call.argument<String>("filePath")
                val expectedBuild = call.argument<Number>("expectedBuild")?.toLong()
                try {
                    require(!filePath.isNullOrBlank()) { "APK 파일 경로가 비어 있습니다." }
                    require(expectedBuild != null && expectedBuild > 0) {
                        "업데이트 빌드 번호가 올바르지 않습니다."
                    }
                    result.success(verifyAndInstallApk(filePath, expectedBuild))
                } catch (error: InstallLaunchException) {
                    result.error(error.code, error.message, null)
                } catch (error: Exception) {
                    result.error("INVALID_APK_UPDATE", error.message ?: "APK 업데이트 검증에 실패했습니다.", null)
                }
            }
    }

    private fun verifyAndInstallApk(filePath: String, expectedBuild: Long): Map<String, Any> {
        val updateDirectory = File(filesDir, "updates").canonicalFile
        val apkFile = File(filePath).canonicalFile
        require(apkFile.parentFile == updateDirectory && apkFile.name.endsWith(".apk", ignoreCase = true)) {
            "허용되지 않은 업데이트 파일 경로입니다."
        }
        require(apkFile.isFile) { "다운로드한 APK 파일을 찾을 수 없습니다." }

        val archiveInfo = getArchivePackageInfo(apkFile)
            ?: throw IllegalArgumentException("APK 패키지 정보를 읽을 수 없습니다.")
        val installedInfo = getInstalledPackageInfo()
        require(archiveInfo.packageName == packageName) { "APK 애플리케이션 ID가 일치하지 않습니다." }
        require(archiveInfo.longVersionCodeCompat() == expectedBuild) {
            "APK 빌드 번호가 업데이트 정보와 일치하지 않습니다."
        }
        require(archiveInfo.longVersionCodeCompat() > installedInfo.longVersionCodeCompat()) {
            "현재 버전과 같거나 낮은 APK는 설치할 수 없습니다."
        }
        require(hasTrustedSigningIdentity(archiveInfo, installedInfo)) {
            "APK 서명 인증서가 설치된 앱과 일치하지 않습니다."
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            openUnknownAppSourcesSettings()
            return installerResult(
                status = STATUS_PERMISSION_REQUIRED,
                message = "설치를 계속하려면 설정에서 Cafe Bridge의 '알 수 없는 앱 설치 허용'을 켠 뒤 앱으로 돌아와 다시 시도해 주세요.",
                canRetry = true,
            )
        }

        val contentUri = FileProvider.getUriForFile(this, "$packageName.updates", apkFile)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, APK_MIME_TYPE)
            clipData = ClipData.newRawUri("Cafe Bridge update", contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            throw InstallLaunchException(
                "INSTALLER_NOT_FOUND",
                "APK를 설치할 수 있는 시스템 앱을 찾지 못했습니다. 기기 관리자 또는 제조사 보안 정책에서 APK 설치 기능이 비활성화되었는지 확인해 주세요.",
            )
        } catch (_: SecurityException) {
            throw InstallLaunchException(
                "INSTALLER_SECURITY_ERROR",
                "기기 보안 정책이 APK 설치 화면 실행을 차단했습니다. 기기 관리자 설정을 확인해 주세요.",
            )
        }
        return installerResult(
            status = STATUS_INSTALLER_OPENED,
            message = "설치 화면을 열었습니다.",
            canRetry = false,
        )
    }

    private fun openUnknownAppSourcesSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            throw InstallLaunchException(
                "INSTALL_PERMISSION_SETTINGS_NOT_FOUND",
                "이 기기에서 앱별 설치 권한 설정 화면을 찾지 못했습니다. 시스템 설정에서 Cafe Bridge의 '알 수 없는 앱 설치' 권한을 직접 허용해 주세요.",
            )
        } catch (_: SecurityException) {
            throw InstallLaunchException(
                "INSTALL_PERMISSION_SETTINGS_BLOCKED",
                "기기 보안 정책이 설치 권한 설정 화면 실행을 차단했습니다. 기기 관리자에게 문의해 주세요.",
            )
        }
    }

    private fun installerResult(
        status: String,
        message: String,
        canRetry: Boolean,
    ): Map<String, Any> = mapOf(
        "status" to status,
        "message" to message,
        "canRetry" to canRetry,
    )

    private class InstallLaunchException(
        val code: String,
        message: String,
    ) : Exception(message)

    @Suppress("DEPRECATION")
    private fun getArchivePackageInfo(file: File): PackageInfo? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return packageManager.getPackageArchiveInfo(file.path, flags)
    }

    @Suppress("DEPRECATION")
    private fun getInstalledPackageInfo(): PackageInfo {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return packageManager.getPackageInfo(packageName, flags)
    }

    @Suppress("DEPRECATION")
    private fun PackageInfo.longVersionCodeCompat(): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) longVersionCode else versionCode.toLong()
    }

    @Suppress("DEPRECATION")
    private fun hasTrustedSigningIdentity(archive: PackageInfo, installed: PackageInfo): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return signatureDigests(archive.signatures.orEmpty()) ==
                signatureDigests(installed.signatures.orEmpty())
        }

        val archiveSigning = archive.signingInfo ?: return false
        val installedSigning = installed.signingInfo ?: return false
        if (archiveSigning.hasMultipleSigners() || installedSigning.hasMultipleSigners()) {
            return archiveSigning.hasMultipleSigners() &&
                installedSigning.hasMultipleSigners() &&
                signatureDigests(archiveSigning.apkContentsSigners.orEmpty()) ==
                signatureDigests(installedSigning.apkContentsSigners.orEmpty())
        }

        val installedCurrent = signatureDigests(installedSigning.apkContentsSigners.orEmpty())
        val archiveHistory = signatureDigests(archiveSigning.signingCertificateHistory.orEmpty())
        return archiveHistory.containsAll(installedCurrent)
    }

    private fun signatureDigests(signatures: Array<out android.content.pm.Signature>): Set<String> {
        require(signatures.isNotEmpty()) { "APK 서명 인증서를 확인할 수 없습니다." }
        return signatures.mapTo(mutableSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }
    }
}
