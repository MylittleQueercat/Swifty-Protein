package com.example.swifty_protein

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

class ShareProvider : ContentProvider() {
    override fun onCreate() = true
    override fun getType(uri: Uri): String? =
        MoleculeImageFormat.fromExtension(imageFile(uri).extension)?.mimeType

    override fun query(
        uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?,
    ): Cursor {
        val image = imageFile(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(columns.map { column ->
                when (column) {
                    OpenableColumns.DISPLAY_NAME -> image.name
                    OpenableColumns.SIZE -> image.length()
                    else -> null
                }
            })
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Images are read only.")
        return ParcelFileDescriptor.open(imageFile(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun imageFile(uri: Uri): File {
        val name = uri.pathSegments.singleOrNull()
        if (name == null || !NAME.matches(name)) throw SecurityException("Invalid image URI.")
        return File(File(requireNotNull(context).cacheDir, IMAGE_DIRECTORY), name)
    }

    companion object {
        const val IMAGE_DIRECTORY = "shared_molecules"
        private val NAME = Regex("SwiftyProtein-[A-Za-z0-9]+-[0-9a-f-]{36}\\.(png|jpg)")
    }
}
