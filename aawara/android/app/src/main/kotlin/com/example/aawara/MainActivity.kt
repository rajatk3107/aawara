package com.example.aawara

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aawara/health_connect_diagnostics"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "inspect" -> result.success(inspectHealthConnectRegistration())
                else -> result.notImplemented()
            }
        }
    }

    private fun inspectHealthConnectRegistration(): Map<String, Any?> {
        val requestedPermissions = requestedPermissions()
        return mapOf(
            "packageName" to packageName,
            "healthConnectPackageVisible" to canSeeHealthConnectPackage(),
            "declaresReadSteps" to requestedPermissions.contains(
                "android.permission.health.READ_STEPS"
            ),
            "declaresActivityRecognition" to requestedPermissions.contains(
                "android.permission.ACTIVITY_RECOGNITION"
            ),
            "requestedPermissions" to requestedPermissions,
            "rationaleHandlers" to queryOwnActivities(
                "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"
            ),
            "android14PermissionUsageHandlers" to queryOwnActivities(
                "android.intent.action.VIEW_PERMISSION_USAGE",
                "android.intent.category.HEALTH_PERMISSIONS"
            ),
            "preAndroid14OnboardingHandlers" to queryOwnActivities(
                "androidx.health.ACTION_SHOW_ONBOARDING"
            ),
            "android14OnboardingHandlers" to queryOwnActivities(
                "android.health.connect.action.SHOW_ONBOARDING"
            )
        )
    }

    private fun requestedPermissions(): List<String> {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        }
        return info.requestedPermissions?.toList() ?: emptyList()
    }

    private fun canSeeHealthConnectPackage(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    "com.google.android.apps.healthdata",
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo("com.google.android.apps.healthdata", 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun queryOwnActivities(action: String, category: String? = null): List<String> {
        val intent = Intent(action).setPackage(packageName)
        if (category != null) intent.addCategory(category)

        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }

        return activities.map { it.activityInfo.name }
    }
}
