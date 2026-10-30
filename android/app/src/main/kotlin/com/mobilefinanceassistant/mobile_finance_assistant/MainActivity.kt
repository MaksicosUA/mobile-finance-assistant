package com.mobilefinanceassistant.mobile_finance_assistant

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.speech.RecognizerIntent
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val privacyChannel = "com.mobilefinanceassistant/privacy_screen"
    private val financeCaptureContextChannel =
        "com.mobilefinanceassistant/finance_capture_context"

    // Handing a downloaded build to the system installer is done here rather
    // than through a package: a third-party plugin standing in the path that
    // installs our own app is trust with no return (ADR 0026).
    private val updateInstallerChannel =
        "com.mobilefinanceassistant/update_installer"

    // A person's own exported record goes to the share sheet and nowhere else;
    // they choose the destination (ADR 0030).
    private val fileShareChannel = "com.mobilefinanceassistant/file_share"

    // Speech goes to Android's own voice input screen, which records and
    // recognises in its own process; only the text comes back (ADR 0031).
    private val speechInputChannel = "com.mobilefinanceassistant/speech_input"
    private var pendingSpeech: MethodChannel.Result? = null

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            updateInstallerChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canRequestInstalls())
                "openInstallPermissionSettings" -> {
                    result.success(openInstallPermissionSettings())
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error(
                            "UPDATE_INSTALL_FAILED",
                            "No package to install.",
                            null,
                        )
                    } else {
                        installDownloadedPackage(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            fileShareChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "share") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val paths = call.argument<List<String>>("paths")
            if (paths.isNullOrEmpty()) {
                result.error("FILE_SHARE_FAILED", "Nothing to share.", null)
            } else {
                shareExportedFiles(paths, result)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            speechInputChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "listen") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            listenForSpeech(
                call.argument<String>("languageTag") ?: "ru-RU",
                call.argument<String>("prompt"),
                result,
            )
        }
    }

    private fun listenForSpeech(
        languageTag: String,
        prompt: String?,
        result: MethodChannel.Result,
    ) {
        // One recogniser at a time: a second answer would have nowhere to go.
        if (pendingSpeech != null) {
            result.success(mapOf("status" to "busy"))
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (prompt != null) putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        try {
            pendingSpeech = result
            startActivityForResult(intent, SPEECH_REQUEST_CODE)
        } catch (_: ActivityNotFoundException) {
            pendingSpeech = null
            result.success(mapOf("status" to "unavailable"))
        } catch (_: RuntimeException) {
            pendingSpeech = null
            result.error("SPEECH_INPUT_FAILED", "The recogniser did not open.", null)
        }
    }

    @Deprecated("FlutterActivity still delivers results through this callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SPEECH_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingSpeech ?: return
        pendingSpeech = null
        // The words are handed over and not kept, logged or looked at here.
        val reply = when (resultCode) {
            Activity.RESULT_OK -> {
                val text = data
                    ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                    ?.firstOrNull()
                    ?.trim()
                if (text.isNullOrEmpty()) {
                    mapOf("status" to "noMatch")
                } else {
                    mapOf("status" to "heard", "text" to text)
                }
            }
            RecognizerIntent.RESULT_NO_MATCH -> mapOf("status" to "noMatch")
            RecognizerIntent.RESULT_NETWORK_ERROR,
            RecognizerIntent.RESULT_SERVER_ERROR,
            -> mapOf("status" to "network")
            RecognizerIntent.RESULT_AUDIO_ERROR,
            RecognizerIntent.RESULT_CLIENT_ERROR,
            -> mapOf("status" to "failed")
            else -> mapOf("status" to "cancelled")
        }
        pending.success(reply)
    }

    private fun shareExportedFiles(paths: List<String>, result: MethodChannel.Result) {
        try {
            val exports = File(cacheDir, "exports").canonicalFile
            val uris = ArrayList<Uri>()
            for (path in paths) {
                val file = File(path).canonicalFile
                // Only files this app exported. Without this the channel could
                // be told to share anything the provider can reach.
                if (!file.path.startsWith(exports.path + File.separator) ||
                    !file.isFile
                ) {
                    result.error(
                        "FILE_SHARE_FAILED",
                        "That file is not one this app exported.",
                        null,
                    )
                    return
                }
                uris.add(FileProvider.getUriForFile(this, "$packageName.updates", file))
            }
            val send = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "*/*"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                // The grant has to ride on ClipData to survive the chooser.
                clipData = ClipData.newRawUri(null, uris.first()).also { clip ->
                    uris.drop(1).forEach { uri -> clip.addItem(ClipData.Item(uri)) }
                }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(
                Intent.createChooser(send, null).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            result.success(null)
        } catch (_: RuntimeException) {
            result.error("FILE_SHARE_FAILED", "The share sheet did not open.", null)
        } catch (_: java.io.IOException) {
            result.error("FILE_SHARE_FAILED", "The share sheet did not open.", null)
        }
    }

    private fun canRequestInstalls(): Boolean {
        // Before API 26 this was one global setting rather than a per-app one,
        // so there is nothing this app can ask for.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun installDownloadedPackage(path: String, result: MethodChannel.Result) {
        try {
            val file = File(path).canonicalFile
            // Only ever a file this app downloaded. Without this the channel
            // could be told to share something else through the provider.
            val updates = File(cacheDir, "updates").canonicalFile
            if (!file.path.startsWith(updates.path + File.separator) ||
                !file.isFile
            ) {
                result.error(
                    "UPDATE_INSTALL_FAILED",
                    "That package is not one this app downloaded.",
                    null,
                )
                return
            }
            // Android refuses a package signed with another key only when it
            // carries this app's name. Under any other name it would install
            // beside this app as something new, and the digest proves nothing
            // about that: it arrives from the same server as the file.
            if (packageManager.getPackageArchiveInfo(file.path, 0)?.packageName !=
                packageName
            ) {
                file.delete()
                result.error(
                    "UPDATE_INSTALL_FAILED",
                    "That package is not this app.",
                    null,
                )
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.updates",
                file,
            )
            // The installer shows its own confirmation, and for this name it
            // refuses anything not signed with the key that signed the
            // installed app.
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            result.success(null)
        } catch (_: RuntimeException) {
            result.error("UPDATE_INSTALL_FAILED", "The installer did not open.", null)
        } catch (_: java.io.IOException) {
            result.error("UPDATE_INSTALL_FAILED", "The installer did not open.", null)
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
        private const val SPEECH_REQUEST_CODE = 4731
        private val unstableTimezoneKeys = setOf("Factory", "localtime", "posixrules")
        private val availableIanaTimezoneKeys = TimeZone.getAvailableIDs().toSet()
        private val utcTimezone: TimeZone = TimeZone.getTimeZone("UTC")
    }
}
