package com.bird.fluidtext

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Copies granted content URIs while access is valid, off the UI thread. */
class ExternalEpubHandler(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "fluidtext/external_epub")
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pending = mutableListOf<Map<String, String>>()
    private val directory = File(context.cacheDir, "external_epub")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingFiles" -> {
                    val files = pending.toList()
                    pending.clear()
                    result.success(files)
                }
                "releaseFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val file = File(path)
                        if (file.canonicalFile.parentFile == directory.canonicalFile) {
                            file.delete()
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun handleIntent(intent: Intent) {
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                } ?: intent.clipData?.let { if (it.itemCount > 0) it.getItemAt(0).uri else null }
            }
            else -> null
        } ?: return
        if (uri.scheme != "content" && uri.scheme != "file") return

        // Capture this Intent's grant before any later onNewIntent changes it.
        executor.execute {
            var name = uri.lastPathSegment ?: "EPUB 文件"
            var copy: File? = null
            val payload = try {
                if (uri.scheme == "content") {
                    context.contentResolver.query(
                        uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
                    )?.use { cursor ->
                        if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
                    }
                }
                require(name.endsWith(".epub", ignoreCase = true) || intent.type == "application/epub+zip") {
                    "The selected file is not an EPUB"
                }
                directory.mkdirs()
                val stagedFile = File.createTempFile("incoming-", ".epub", directory)
                copy = stagedFile
                val source = context.contentResolver.openInputStream(uri)
                    ?: throw IllegalArgumentException("Unable to open EPUB stream")
                source.use { input -> stagedFile.outputStream().use { output -> input.copyTo(output) } }
                mapOf("name" to name, "path" to stagedFile.absolutePath)
            } catch (error: Exception) {
                copy?.delete()
                mapOf("name" to name, "error" to (error.message ?: "Unable to read EPUB"))
            }
            mainHandler.post {
                pending.add(payload)
                channel.invokeMethod("filesAvailable", null)
            }
        }
    }
}
