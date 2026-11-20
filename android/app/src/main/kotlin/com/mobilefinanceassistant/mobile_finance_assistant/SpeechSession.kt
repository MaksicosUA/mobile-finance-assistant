package com.mobilefinanceassistant.mobile_finance_assistant

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.EventChannel

/**
 * Listens through pauses until the person says they are done (ADR 0031
 * amendment).
 *
 * The phone's recognition service records and recognises; this class is
 * handed text and nothing else. Audio buffers the service may offer are never
 * kept. A recogniser ends its turn at the first pause, so each turn is
 * restarted at once and the words are joined, and listening stops only when
 * the person taps Done, after a long silence, or at a hard limit, so a
 * microphone is never left on by accident.
 */
class SpeechSession(
    private val context: Context,
    private val languageTag: String,
    private val events: EventChannel.EventSink,
    private val onEnded: () -> Unit,
) : RecognitionListener {

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private val segments = mutableListOf<String>()
    private var partial = ""
    private var startedAt = 0L
    private var lastHeardAt = 0L
    private var finishing = false
    private var ended = false
    private var quickFailures = 0

    private val watch = object : Runnable {
        override fun run() {
            if (ended) return
            val now = SystemClock.elapsedRealtime()
            when {
                now - startedAt >= SESSION_LIMIT_MS -> end("done")
                now - lastHeardAt >= SILENCE_LIMIT_MS -> end("silence")
                else -> handler.postDelayed(this, WATCH_INTERVAL_MS)
            }
        }
    }

    val isOpen: Boolean
        get() = !ended

    fun start() {
        startedAt = SystemClock.elapsedRealtime()
        lastHeardAt = startedAt
        val created = try {
            SpeechRecognizer.createSpeechRecognizer(context)
        } catch (_: RuntimeException) {
            null
        }
        if (created == null) {
            end("unavailable")
            return
        }
        recognizer = created
        created.setRecognitionListener(this)
        emitText()
        listenOnce()
        handler.postDelayed(watch, WATCH_INTERVAL_MS)
    }

    /** The person is done: what is being said now is still taken. */
    fun finish() {
        if (ended || finishing) return
        finishing = true
        try {
            recognizer?.stopListening()
        } catch (_: RuntimeException) {
            end("done")
            return
        }
        // A recogniser that never answers the stop must not hold the screen.
        handler.postDelayed({ end("done") }, FINISH_GRACE_MS)
    }

    /** The person changed their mind: nothing heard goes anywhere. */
    fun cancel() {
        if (ended) return
        segments.clear()
        partial = ""
        end("cancelled")
    }

    private fun listenOnce() {
        if (ended) return
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            // Hints only: many recognisers ignore them. The restart in
            // onResults and onError is what actually keeps listening.
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                TURN_SILENCE_HINT_MS,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                TURN_SILENCE_HINT_MS,
            )
        }
        try {
            recognizer?.startListening(intent)
        } catch (_: RuntimeException) {
            end("failed")
        }
    }

    private fun restart(delayMs: Long = RESTART_DELAY_MS) {
        if (ended) return
        // Words a turn showed but never confirmed are still words said.
        if (partial.isNotBlank()) {
            segments.add(partial.trim())
            partial = ""
        }
        try {
            recognizer?.cancel()
        } catch (_: RuntimeException) {
            // Starting again below is what matters.
        }
        handler.postDelayed({ listenOnce() }, delayMs)
    }

    private fun heardNow() {
        lastHeardAt = SystemClock.elapsedRealtime()
    }

    private fun text(): String {
        val words = segments.toMutableList()
        if (partial.isNotBlank()) words.add(partial.trim())
        return words.joinToString(" ").trim()
    }

    private fun emitText() {
        if (ended) return
        events.success(mapOf("type" to "text", "text" to text()))
    }

    private fun end(reason: String) {
        if (ended) return
        ended = true
        handler.removeCallbacksAndMessages(null)
        val heard = if (reason == "cancelled") "" else text()
        segments.clear()
        partial = ""
        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: RuntimeException) {
            // The recogniser is gone either way.
        }
        recognizer = null
        events.success(mapOf("type" to "ended", "reason" to reason, "text" to heard))
        events.endOfStream()
        onEnded()
    }

    override fun onReadyForSpeech(params: Bundle?) {}

    override fun onBeginningOfSpeech() {
        quickFailures = 0
        heardNow()
    }

    override fun onRmsChanged(rmsdB: Float) {}

    // Audio is never kept, looked at or passed on.
    override fun onBufferReceived(buffer: ByteArray?) {}

    override fun onEndOfSpeech() {}

    override fun onEvent(eventType: Int, params: Bundle?) {}

    override fun onPartialResults(partialResults: Bundle?) {
        val words = first(partialResults) ?: return
        if (words.isBlank()) return
        partial = words
        heardNow()
        emitText()
    }

    override fun onResults(results: Bundle?) {
        if (ended) return
        quickFailures = 0
        val words = first(results)
        partial = ""
        if (!words.isNullOrBlank()) {
            segments.add(words.trim())
            heardNow()
        }
        emitText()
        if (finishing) end("done") else restart()
    }

    override fun onError(error: Int) {
        if (ended) return
        if (finishing) {
            end("done")
            return
        }
        when (error) {
            // A pause, or a turn that heard nothing: listen again. The watch
            // decides when silence has gone on long enough.
            SpeechRecognizer.ERROR_NO_MATCH,
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
            -> restart()
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
            SpeechRecognizer.ERROR_CLIENT,
            -> {
                quickFailures += 1
                if (quickFailures > MAX_QUICK_FAILURES) end("failed") else restart(BUSY_DELAY_MS)
            }
            SpeechRecognizer.ERROR_NETWORK,
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
            SpeechRecognizer.ERROR_SERVER,
            ERROR_SERVER_DISCONNECTED,
            ERROR_LANGUAGE_NOT_SUPPORTED,
            ERROR_LANGUAGE_UNAVAILABLE,
            -> end("network")
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> end("permissionDenied")
            else -> end("failed")
        }
    }

    private fun first(bundle: Bundle?): String? =
        bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()

    private companion object {
        /** How long a silence ends listening on its own. */
        const val SILENCE_LIMIT_MS = 15_000L

        /** No session outlives this, whatever is said. */
        const val SESSION_LIMIT_MS = 180_000L

        const val FINISH_GRACE_MS = 2_500L
        const val WATCH_INTERVAL_MS = 500L
        const val RESTART_DELAY_MS = 150L
        const val BUSY_DELAY_MS = 500L
        const val MAX_QUICK_FAILURES = 5
        const val TURN_SILENCE_HINT_MS = 4_000L

        // Added in API 31; the values are what older phones would never send.
        const val ERROR_SERVER_DISCONNECTED = 11
        const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        const val ERROR_LANGUAGE_UNAVAILABLE = 13
    }
}
