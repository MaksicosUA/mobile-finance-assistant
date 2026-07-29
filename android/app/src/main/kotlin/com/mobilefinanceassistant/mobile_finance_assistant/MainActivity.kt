package com.mobilefinanceassistant.mobile_finance_assistant

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val privacyChannel = "com.mobilefinanceassistant/privacy_screen"
    private val financeCaptureContextChannel =
        "com.mobilefinanceassistant/finance_capture_context"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, privacyChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "setProtected") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val enabled = call.argument<Boolean>("enabled") ?: false
                window.decorView.post {
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
            }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            financeCaptureContextChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "capture") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val arguments = call.arguments
            val canonicalTimezone =
                if (arguments is Map<*, *> &&
                    arguments.size == 1 &&
                    arguments.keys.singleOrNull() == "canonicalTimezone"
                ) {
                    arguments["canonicalTimezone"] as? String
                } else {
                    null
                }
            val canonicalZone = stableIanaTimezone(canonicalTimezone)
            if (canonicalTimezone == null || canonicalZone == null) {
                result.error(
                    "CAPTURE_CONTEXT_UNAVAILABLE",
                    "Finance capture context is unavailable.",
                    null,
                )
                return@setMethodCallHandler
            }

            try {
                val capturedAtMillis = System.currentTimeMillis()
                val osTimezone = TimeZone.getDefault().id
                val osZone = stableIanaTimezone(osTimezone)
                if (osZone == null) {
                    result.error(
                        "CAPTURE_CONTEXT_UNAVAILABLE",
                        "Finance capture context is unavailable.",
                        null,
                    )
                    return@setMethodCallHandler
                }

                result.success(
                    mapOf(
                        "capturedAtUtc" to utcInstant(capturedAtMillis),
                        "osTimezone" to osTimezone,
                        "osLocalDate" to localDate(capturedAtMillis, osZone),
                        "canonicalTimezone" to canonicalTimezone,
                        "canonicalLocalDate" to localDate(capturedAtMillis, canonicalZone),
                    ),
                )
            } catch (_: RuntimeException) {
                result.error(
                    "CAPTURE_CONTEXT_UNAVAILABLE",
                    "Finance capture context is unavailable.",
                    null,
                )
            }
        }
    }

    private fun stableIanaTimezone(value: String?): TimeZone? {
        if (value == null ||
            value.isEmpty() ||
            value.length > 128 ||
            value != value.trim() ||
            value in unstableTimezoneKeys ||
            value.any { character -> character.code < 0x20 || character.code == 0x7f }
        ) {
            return null
        }
        if (!availableIanaTimezoneKeys.contains(value)) {
            return null
        }
        return TimeZone.getTimeZone(value).takeIf { timezone -> timezone.id == value }
    }

    private fun utcInstant(capturedAtMillis: Long): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT)
        formatter.isLenient = false
        formatter.timeZone = utcTimezone
        return formatter.format(Date(capturedAtMillis))
    }

    private fun localDate(capturedAtMillis: Long, timezone: TimeZone): String {
        val calendar = GregorianCalendar(timezone, Locale.ROOT)
        calendar.isLenient = false
        calendar.timeInMillis = capturedAtMillis
        return String.format(
            Locale.ROOT,
            "%04d-%02d-%02d",
            calendar.get(GregorianCalendar.YEAR),
            calendar.get(GregorianCalendar.MONTH) + 1,
            calendar.get(GregorianCalendar.DAY_OF_MONTH),
        )
    }

    private companion object {
        private val unstableTimezoneKeys = setOf("Factory", "localtime", "posixrules")
        private val availableIanaTimezoneKeys = TimeZone.getAvailableIDs().toSet()
        private val utcTimezone: TimeZone = TimeZone.getTimeZone("UTC")
    }
}
