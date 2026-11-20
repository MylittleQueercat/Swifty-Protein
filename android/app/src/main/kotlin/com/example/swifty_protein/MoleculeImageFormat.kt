package com.example.swifty_protein

import android.graphics.Bitmap

internal enum class MoleculeImageFormat(
    val key: String,
    val extension: String,
    val mimeType: String,
    val compression: Bitmap.CompressFormat,
    val quality: Int,
) {
    PNG("png", "png", "image/png", Bitmap.CompressFormat.PNG, 100),
    JPEG("jpeg", "jpg", "image/jpeg", Bitmap.CompressFormat.JPEG, 92);

    companion object {
        fun fromKey(value: Any?): MoleculeImageFormat? = entries.firstOrNull { it.key == value }
        fun fromExtension(value: String): MoleculeImageFormat? = entries.firstOrNull { it.extension == value }
    }
}
