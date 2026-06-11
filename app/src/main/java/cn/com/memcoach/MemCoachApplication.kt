package cn.com.memcoach

import android.app.Application
import cn.com.memcoach.agent.llm.OpenAICompatibleAgentLlmClient
import cn.com.memcoach.data.AppDatabase
import cn.com.memcoach.pipeline.PdfPipelineService

class MemCoachApplication : Application() {
    companion object {
        lateinit var instance: MemCoachApplication
            private set
    }

    lateinit var pipelineService: PdfPipelineService
        private set

    lateinit var llmClient: OpenAICompatibleAgentLlmClient
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this

        val database = AppDatabase.getInstance(this)
        llmClient = OpenAICompatibleAgentLlmClient(
            baseUrl = "https://api.deepseek.com/v1",
            apiKey = "sk-5128e904815840ebaaa819d395da66c1",
            defaultModel = "deepseek-v4-flash"
        )
        pipelineService = PdfPipelineService(
            context = this,
            questionDao = database.examQuestionDao(),
            llmClient = llmClient
        )
    }
}

