package com.example.swifty_protein

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import kotlin.concurrent.thread

internal class MoleculeImages(private val activity: Activity) {
    private data class Export(
        val bytes: ByteArray, val name: String, val format: MoleculeImageFormat,
    )

    private data class PendingSave(
        val image: Export, val reply: MethodChannel.Result,
    )
    private var pendingSave: PendingSave? = null

    fun handle(call: MethodCall, reply: MethodChannel.Result) {
        if (call.method != "share" && call.method != "save") {
            reply.notImplemented()
            return
        }
        val bytes = call.argument<ByteArray>("image")
        val format = MoleculeImageFormat.fromKey(call.argument<String>("format"))
        if (bytes == null || bytes.isEmpty() || bytes.size > 20_000_000) {
            reply.error("invalid_image", "Missing image or image too large.", null)
            return
        }
        if (format == null) {
            reply.error("invalid_format", "Unsupported image format.", null)
            return
        }
        val id = call.argument<String>("id").orEmpty()
        val filenameId = id.filter { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' }
            .take(16).ifEmpty { "molecule" }
        val image = Export(bytes, "SwiftyProtein-$filenameId-${UUID.randomUUID()}.${format.extension}", format)
        when {
            call.method == "share" -> share(
                image, call.argument<String>("title"), call.argument<String>("message"), reply,
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                background(reply) { saveToPhotos(image) }
            else -> saveWithLegacyPermission(image, reply)
        }
    }

    private fun share(image: Export, title: String?, message: String?, reply: MethodChannel.Result) {
        thread(name = "molecule-share") {
            val prepared = runCatching {
                val directory = File(activity.cacheDir, ShareProvider.IMAGE_DIRECTORY)
                check(directory.isDirectory || directory.mkdirs())
                val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000
                directory.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
                File(directory, image.name).writeBytes(image.bytes)
                Uri.Builder().scheme("content").authority("${activity.packageName}.share")
                    .appendPath(image.name).build()
            }
            activity.runOnUiThread {
                try {
                    val uri = prepared.getOrThrow()
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = image.format.mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        if (!title.isNullOrBlank()) putExtra(Intent.EXTRA_SUBJECT, title)
                        if (!message.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, message)
                        clipData = ClipData.newUri(activity.contentResolver, image.name, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    activity.startActivity(Intent.createChooser(intent, "Share molecule"))
                    reply.success(true)
                } catch (error: Exception) {
                    reply.error("share_failed", error.message, null)
                }
            }
        }
    }

    private fun saveToPhotos(image: Export) {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, image.name)
            put(MediaStore.Images.Media.MIME_TYPE, image.format.mimeType)
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Swifty Protein")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = checkNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
        try {
            checkNotNull(resolver.openOutputStream(uri)).use { it.write(image.bytes) }
            val ready = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            check(resolver.update(uri, ready, null, null) == 1)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun saveWithLegacyPermission(image: Export, reply: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            == PackageManager.PERMISSION_GRANTED
        ) {
            background(reply) { saveLegacyPhoto(image) }
            return
        }
        if (pendingSave != null) {
            reply.error("save_busy", "Another image is being saved.", null)
            return
        }
        pendingSave = PendingSave(image, reply)
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), WRITE_PHOTOS)
        } catch (error: Exception) {
            pendingSave = null
            reply.error("save_failed", error.message, null)
        }
    }

    fun finishLegacyPermission(grantResults: IntArray) {
        val save = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) {
            save.reply.error("permission_denied", "Allow storage access to save to photos.", null)
            return
        }
        background(save.reply) { saveLegacyPhoto(save.image) }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacyPhoto(image: Export) {
        val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val directory = File(pictures, "Swifty Protein")
        check(directory.isDirectory || directory.mkdirs())
        val file = File(directory, image.name)
        try {
            file.writeBytes(image.bytes)
            MediaScannerConnection.scanFile(activity, arrayOf(file.path), arrayOf(image.format.mimeType), null)
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    private fun background(reply: MethodChannel.Result, save: () -> Unit) {
        thread(name = "molecule-save") {
            val result = runCatching(save)
            activity.runOnUiThread {
                result.fold(
                    onSuccess = { reply.success(true) },
                    onFailure = { reply.error("save_failed", it.message, null) },
                )
            }
        }
    }

    companion object {
        const val WRITE_PHOTOS = 3718
    }
}
