package com.example.swift_chat

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val systemChannel = "swift_chat/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> result.success(getAppVersionInfo())
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        result.success(openUrl(url))
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
}
