package com.example.netdisk

import android.net.Uri
import android.os.Bundle
import org.json.JSONObject

data class UploadItem(
    val uri: Uri,
    val name: String,
    val folderPath: String,
    val size: Long
) {
    fun toBundle(): Bundle = Bundle().apply {
        putString("uri", uri.toString())
        putString("name", name)
        putString("folderPath", folderPath)
        putLong("size", size)
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("uri", uri.toString())
        put("name", name)
        put("folderPath", folderPath)
        put("size", size)
    }

    companion object {
        fun fromBundle(b: Bundle): UploadItem = UploadItem(
            Uri.parse(b.getString("uri")!!),
            b.getString("name")!!,
            b.getString("folderPath") ?: "",
            b.getLong("size")
        )

        fun fromJson(o: JSONObject): UploadItem = UploadItem(
            Uri.parse(o.getString("uri")),
            o.getString("name"),
            o.optString("folderPath", ""),
            o.getLong("size")
        )
    }
}
