package com.swift.chat.android

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val systemChannel = "swift_chat/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> result.success(getAppVersionInfo())
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        result.success(openUrl(url))
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        result.success(installApk(filePath))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getAppVersionInfo(): Map<String, String> {
        val packageInfo = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }

        @Suppress("DEPRECATION")
        val buildNumber = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            packageInfo.versionCode.toString()
        }

        return mapOf(
            "versionName" to (packageInfo.versionName ?: ""),
            "buildNumber" to buildNumber,
            "packageName" to packageName,
        )
    }

    private fun openUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) {
            return false
        }

        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun installApk(filePath: String?): String {
        if (filePath.isNullOrBlank()) {
            return "failed"
        }

        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            return "failed"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            openUnknownAppsSettings()
            return "needs_permission"
        }

        return try {
            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile
            )

            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivity(installIntent)
            "started"
        } catch (_: Exception) {
            "failed"
        }
    }

    private fun openUnknownAppsSettings() {
        try {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(settingsIntent)
        } catch (_: ActivityNotFoundException) {
            val fallbackIntent = Intent(Settings.ACTION_SECURITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallbackIntent)
        }
    }
}
