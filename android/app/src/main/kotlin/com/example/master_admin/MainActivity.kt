package com.example.master_admin

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Master Admin on Android:
 * · Screenshots and screen recording are blocked (FLAG_SECURE); the app
 *   also shows blank in the recent-apps list. Flutter can switch it with
 *   the "ma/secure" channel (setSecure true/false).
 * · Word, PowerPoint, Excel and CSV files opened with "Open with › Master
 *   Admin" (WhatsApp, Telegram, Files …) are handed to the app through the
 *   "ma/launch_files" channel (takeFiles → list of {name, bytes}).
 */
class MainActivity : FlutterActivity() {
    private val pending = mutableListOf<Map<String, Any>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        keepFiles(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        keepFiles(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "ma/secure").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    if (call.arguments == true) {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "ma/launch_files").setMethodCallHandler { call, result ->
            when (call.method) {
                "takeFiles" -> {
                    val out = ArrayList(pending)
                    pending.clear()
                    result.success(out)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Reads the file(s) of a VIEW / SEND intent (at most 20 MB each). */
    private fun keepFiles(intent: Intent?) {
        if (intent == null) return
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            }
        }
        for (uri in uris) {
            try {
                var name = uri.lastPathSegment ?: "file"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (i >= 0) c.getString(i)?.let { name = it }
                    }
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: continue
                if (bytes.size <= 20 * 1024 * 1024) pending.add(mapOf("name" to name, "bytes" to bytes))
            } catch (_: Exception) {
            }
        }
        // handled: don't hand the same file over again when the app is recreated
        intent.action = Intent.ACTION_MAIN
    }
}
