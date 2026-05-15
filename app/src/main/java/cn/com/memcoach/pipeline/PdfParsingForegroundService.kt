package cn.com.memcoach.pipeline

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import cn.com.memcoach.MainActivity
import cn.com.memcoach.data.AppDatabase
import cn.com.memcoach.agent.llm.AgentLlmRouter
import cn.com.memcoach.agent.llm.OpenAICompatibleAgentLlmClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

/**
 * PDF 解析前台服务 —— 确保长时解析任务不被系统回收。
 */
class PdfParsingForegroundService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var pipelineService: PdfPipelineService

    companion object {
        private const val CHANNEL_ID = "pdf_parsing_channel"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context, filePath: String, subject: String, year: Int, jobId: String) {
            val intent = Intent(context, PdfParsingForegroundService::class.java).apply {
                putExtra("file_path", filePath)
                putExtra("subject", subject)
                putExtra("year", year)
                putExtra("job_id", jobId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        // 临时初始化 Pipeline（实际应通过 DI 或 Application 获取）
        val db = AppDatabase.getInstance(applicationContext)
        val llmClient = OpenAICompatibleAgentLlmClient(
            baseUrl = "https://wzw.pp.ua/v1",
            apiKey = "", // 运行时会从配置加载
            defaultModel = "deepseek-ai/deepseek-v4-flash"
        )
        pipelineService = PdfPipelineService(applicationContext, db.examQuestionDao(), llmClient)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val filePath = intent?.getStringExtra("file_path") ?: return START_NOT_STICKY
        val subject = intent.getStringExtra("subject") ?: "unknown"
        val year = intent.getIntExtra("year", 0)
        val jobId = intent.getStringExtra("job_id") ?: "job_${System.currentTimeMillis()}"

        val notification = createNotification("正在准备解析...")
        startForeground(NOTIFICATION_ID, notification)

        serviceScope.launch {
            try {
                pipelineService.processPdf(
                    pdfFile = File(filePath),
                    subject = subject,
                    year = year,
                    jobId = jobId,
                    callback = object : PdfPipelineService.ProgressCallback {
                        override fun onStepChange(step: String) {}
                        override fun onProgress(progress: Int) {
                            updateNotification("正在解析真题：$progress%")
                        }
                        override fun onMessage(message: String) {
                            updateNotification(message)
                        }
                        override fun onError(error: String) {
                            stopForeground(true)
                            stopSelf()
                        }
                    }
                )
            } catch (e: Exception) {
                // 处理异常
            } finally {
                stopForeground(true)
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "PDF 解析服务",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(content: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MEM Coach 智能分析")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(content: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, createNotification(content))
    }
}
