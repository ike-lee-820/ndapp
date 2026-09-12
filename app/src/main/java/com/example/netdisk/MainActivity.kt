package com.example.netdisk

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import com.example.netdisk.databinding.ActivityMainBinding
import org.json.JSONArray

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences("netdisk", Context.MODE_PRIVATE) }

    private val uploadQueue = mutableListOf<UploadItem>()

    private val pickFiles = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris ->
        if (uris.isNullOrEmpty()) return@registerForActivityResult
        uris.forEach { uri ->
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: Exception) {}
            val name = getFileName(uri) ?: "unknown"
            val size = getFileSize(uri)
            uploadQueue.add(UploadItem(uri, name, "", size))
        }
        updateQueueUI()
    }

    private val pickFolder = registerForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        if (uri == null) return@registerForActivityResult
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {}
        val root = DocumentFile.fromTreeUri(this, uri) ?: return@registerForActivityResult
        val rootName = root.name ?: "folder"
        val items = collectFolderFiles(root, rootName)
        uploadQueue.addAll(items)
        updateQueueUI()
        Toast.makeText(this, "已添加 ${items.size} 个文件", Toast.LENGTH_SHORT).show()
    }

    private val requestNotification = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            Toast.makeText(this, "未授予通知权限，上传进度将不可见", Toast.LENGTH_LONG).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.etWorkerUrl.setText(prefs.getString("workerUrl", ""))
        binding.etPassword.setText(prefs.getString("password", ""))
        binding.etBaseFolder.setText(prefs.getString("baseFolder", ""))

        binding.btnSave.setOnClickListener {
            prefs.edit()
                .putString("workerUrl", binding.etWorkerUrl.text.toString().trim())
                .putString("password", binding.etPassword.text.toString())
                .putString("baseFolder", binding.etBaseFolder.text.toString().trim())
                .apply()
            Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show()
        }

        binding.btnPickFiles.setOnClickListener { pickFiles.launch(arrayOf("*/*")) }
        binding.btnPickFolder.setOnClickListener { pickFolder.launch(null) }

        binding.btnClear.setOnClickListener {
            uploadQueue.clear()
            updateQueueUI()
        }

        binding.btnStart.setOnClickListener { startUpload() }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestNotification.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    private fun updateQueueUI() {
        val count = uploadQueue.size
        val totalSize = uploadQueue.sumOf { it.size }
        binding.tvQueueInfo.text = "待上传: $count 个文件，总大小 ${formatSize(totalSize)}"
    }

    private fun startUpload() {
        val workerUrl = binding.etWorkerUrl.text.toString().trim().trimEnd('/')
        val password = binding.etPassword.text.toString()
        val baseFolder = binding.etBaseFolder.text.toString().trim().trim('/')

        if (workerUrl.isEmpty()) {
            Toast.makeText(this, "请填写 Worker 地址", Toast.LENGTH_SHORT).show()
            return
        }
        if (uploadQueue.isEmpty()) {
            Toast.makeText(this, "请先选择文件/文件夹", Toast.LENGTH_SHORT).show()
            return
        }

        val tempFile = java.io.File(cacheDir, "upload_queue.json")
        val arr = JSONArray()
        uploadQueue.forEach { arr.put(it.toJson()) }
        tempFile.writeText(arr.toString())

        val intent = Intent(this, UploadService::class.java).apply {
            putExtra("workerUrl", workerUrl)
            putExtra("password", password)
            putExtra("baseFolder", baseFolder)
            putExtra("queueFile", tempFile.absolutePath)
        }
        ContextCompat.startForegroundService(this, intent)

        uploadQueue.clear()
        updateQueueUI()
        Toast.makeText(this, "已开始后台上传", Toast.LENGTH_SHORT).show()
    }

    private fun getFileName(uri: Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) return cursor.getString(idx)
            }
        }
        return uri.lastPathSegment
    }

    private fun getFileSize(uri: Uri): Long {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                if (idx >= 0) return cursor.getLong(idx)
            }
        }
        return 0L
    }

    private fun collectFolderFiles(folder: DocumentFile, relativePath: String): List<UploadItem> {
        val result = mutableListOf<UploadItem>()
        for (file in folder.listFiles()) {
            if (file.isDirectory) {
                result.addAll(collectFolderFiles(file, "$relativePath/${file.name}"))
            } else if (file.isFile) {
                result.add(
                    UploadItem(
                        file.uri,
                        file.name ?: "unknown",
                        relativePath,
                        file.length()
                    )
                )
            }
        }
        return result
    }

    private fun formatSize(b: Long): String {
        if (b < 1024) return "$b B"
        val kb = b / 1024.0
        if (kb < 1024) return "%.1f KB".format(kb)
        val mb = kb / 1024.0
        if (mb < 1024) return "%.1f MB".format(mb)
        return "%.2f GB".format(mb / 1024)
    }
}
