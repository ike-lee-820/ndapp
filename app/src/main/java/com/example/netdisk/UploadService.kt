package com.example.netdisk

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Base64
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.TimeUnit

class UploadService : Service() {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(300, TimeUnit.SECONDS)
        .writeTimeout(300, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private val NOTIF_ID = 1001
    private lateinit var notificationManager: NotificationManager
    private val CLIENT_CHUNK_SIZE = 20L * 1024 * 1024

    companion object {
        const val CHANNEL_ID = "netdisk_upload"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIF_ID, buildNotification("准备上传", "正在初始化...", 0, true))

        val workerUrl = intent?.getStringExtra("workerUrl") ?: run { stopSelf(); return START_NOT_STICKY }
        val password = intent.getStringExtra("password") ?: ""
        val baseFolder = intent.getStringExtra("baseFolder") ?: ""
        val queueFile = intent.getStringExtra("queueFile") ?: run { stopSelf(); return START_NOT_STICKY }

        scope.launch {
            try {
                val items = loadQueue(queueFile)
                uploadAll(workerUrl, password, baseFolder, items)
            } catch (e: Exception) {
                e.printStackTrace()
                updateNotification("上传失败", e.message ?: "未知错误", 0, false)
            } finally {
                delay(3000)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun loadQueue(path: String): List<UploadItem> {
        val file = File(path)
        if (!file.exists()) return emptyList()
        val arr = JSONArray(file.readText())
        val list = mutableListOf<UploadItem>()
        for (i in 0 until arr.length()) list.add(UploadItem.fromJson(arr.getJSONObject(i)))
        file.delete()
        return list
    }

    private suspend fun uploadAll(workerUrl: String, password: String, baseFolder: String, items: List<UploadItem>) {
        val total = items.size
        var success = 0
        var fail = 0
        for ((idx, item) in items.withIndex()) {
            try {
                uploadOne(workerUrl, password, baseFolder, item, idx, total)
                success++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                e.printStackTrace()
                fail++
            }
            System.gc()
            delay(300)
        }
        updateNotification("全部完成", "成功 $success / 失败 $fail（共 $total）", 100, false)
    }

    private suspend fun uploadOne(
        workerUrl: String, password: String, baseFolder: String,
        item: UploadItem, idx: Int, total: Int
    ) {
        val rel = item.folderPath.trim('/')
        val filePath = buildString {
            if (baseFolder.isNotEmpty()) append(baseFolder).append('/')
            if (rel.isNotEmpty()) append(rel).append('/')
            append(item.name)
        }
        val taskId = "android_" + System.currentTimeMillis() + "_" + (10000..99999).random()

        updateNotification("上传 (${idx + 1}/$total)", "${item.name} - 初始化...", idx * 100 / total, true)

        val startBody = JSONObject().apply {
            put("path", filePath)
            put("filename", item.name)
            put("size", item.size)
            put("taskId", taskId)
        }.toString()

        val startResp = postJson("$workerUrl/api/upload/manual/start", startBody, password)
        val uploadId = startResp.getString("uploadId")
        val githubUser = startResp.getString("githubUser")
        val repo = startResp.getString("repo")
        val token = startResp.getString("token")

        val chunks = if (item.size == 0L) 1 else Math.ceil(item.size.toDouble() / CLIENT_CHUNK_SIZE).toInt()

        val inputStream = contentResolver.openInputStream(item.uri)
            ?: throw IOException("无法打开文件: ${item.name}")

        inputStream.use { stream ->
            val buffer = ByteArray(CLIENT_CHUNK_SIZE.toInt())
            var index = 0
            var sentBytes = 0L

            while (index < chunks) {
                val chunk = readChunk(stream, buffer, CLIENT_CHUNK_SIZE.toInt())
                if (chunk.isEmpty() && sentBytes >= item.size) break

                val base64 = Base64.encodeToString(chunk, Base64.NO_WRAP)
                val sha = githubPutChunkWithRetry(githubUser, repo, index, base64, token)

                try {
                    val notifyBody = JSONObject().apply {
                        put("uploadId", uploadId)
                        put("index", index)
                        put("sha", sha)
                        put("total", chunks)
                        put("taskId", taskId)
                    }.toString()
                    postJson("$workerUrl/api/upload/manual/chunk", notifyBody, password)
                } catch (e: Exception) {
                    e.printStackTrace()
                }

                sentBytes += chunk.size
                index++

                val filePct = (sentBytes.toFloat() / item.size.coerceAtLeast(1) * 100).toInt().coerceIn(0, 100)
                val overallPct = ((idx + sentBytes.toFloat() / item.size.coerceAtLeast(1)) / total * 100).toInt()
                updateNotification(
                    "上传 (${idx + 1}/$total)",
                    "${item.name} - $filePct% ($index/$chunks 分片)",
                    overallPct, true
                )
                yield()
            }
        }

        val finishBody = JSONObject().apply {
            put("uploadId", uploadId)
            put("path", filePath)
            put("filename", item.name)
            put("size", item.size)
            put("chunks", chunks)
            put("taskId", taskId)
        }.toString()
        postJson("$workerUrl/api/upload/manual/finish", finishBody, password)
    }

    private fun readChunk(stream: InputStream, buffer: ByteArray, size: Int): ByteArray {
        var totalRead = 0
        while (totalRead < size) {
            val read = stream.read(buffer, totalRead, size - totalRead)
            if (read < 0) break
            totalRead += read
        }
        return if (totalRead == size) buffer.copyOf(size) else buffer.copyOf(totalRead)
    }

    private fun githubPutChunkWithRetry(user: String, repo: String, index: Int, base64: String, token: String): String {
        var lastError: Exception? = null
        for (attempt in 1..3) {
            try {
                return githubPutChunk(user, repo, index, base64, token)
            } catch (e: Exception) {
                lastError = e
                e.printStackTrace()
                if (attempt < 3) Thread.sleep(1500L * attempt)
            }
        }
        throw lastError ?: IOException("GitHub 上传失败")
    }

    private fun githubPutChunk(user: String, repo: String, index: Int, base64: String, token: String): String {
        val body = JSONObject().apply {
            put("message", "chunk $index")
            put("content", base64)
        }.toString()

        val req = Request.Builder()
            .url("https://api.github.com/repos/$user/$repo/contents/chunk_$index")
            .put(body.toRequestBody("application/json".toMediaType()))
            .header("Authorization", "token $token")
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "netdisk-android")
            .build()

        client.newCall(req).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IOException("GitHub ${resp.code}: ${text.take(200)}")
            return JSONObject(text).getJSONObject("content").getString("sha")
        }
    }

    private fun postJson(url: String, body: String, password: String): JSONObject {
        val req = Request.Builder()
            .url(url)
            .post(body.toRequestBody("application/json".toMediaType()))
            .header("X-Password", password)
            .header("Content-Type", "application/json")
            .build()
        client.newCall(req).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}: ${text.take(200)}")
            return JSONObject(text)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "上传进度", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示文件上传进度"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, text: String, progress: Int, indeterminate: Boolean): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, indeterminate)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .build()
    }

    private fun updateNotification(title: String, text: String, progress: Int, indeterminate: Boolean) {
        try {
            notificationManager.notify(NOTIF_ID, buildNotification(title, text, progress, indeterminate))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
