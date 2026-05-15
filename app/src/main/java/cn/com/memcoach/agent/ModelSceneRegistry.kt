package cn.com.memcoach.agent

import android.content.Context
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * 模型场景注册表 —— 统一管理 Prompt 场景配置
 *
 * 设计借鉴：OpenOmniBot ModelSceneRegistry 的场景化管理机制。
 *
 * 核心功能：
 * 1. 从外部 JSON 配置文件加载场景定义
 * 2. 支持 {{KEY}} 占位符动态渲染
 * 3. 支持多语言 prompt（prompt_i18n）
 * 4. 提供场景查询和解析接口
 *
 * 场景配置文件位置：
 *   app/src/main/res/raw/model_scenes_default.json
 *
 * 场景格式：
 * {
 *   "scene.xxx": {
 *     "model": "qwen-plus",
 *     "prompt": "场景提示词...",
 *     "prompt_i18n": {
 *       "zh-CN": "中文提示词...",
 *       "en-US": "English prompt..."
 *     },
 *     "description": "场景描述",
 *     "description_i18n": {...}
 *   }
 * }
 */
class ModelSceneRegistry(
    private val context: Context
) {
    companion object {
        /** 默认场景配置文件 */
        private const val DEFAULT_SCENES_FILE = "model_scenes_default"

        /** 默认语言 */
        private const val DEFAULT_LANGUAGE = "zh-CN"
    }

    /** 场景配置缓存 */
    private val scenes = mutableMapOf<String, SceneConfig>()

    /** 是否已加载 */
    private var loaded = false

    /**
     * 场景配置
     */
    data class SceneConfig(
        val sceneId: String,
        val model: String,
        val prompt: String,
        val promptI18n: Map<String, String> = emptyMap(),
        val description: String = "",
        val descriptionI18n: Map<String, String> = emptyMap(),
        val transport: String = "openai_compatible",
        val responseParser: String = "text_content"
    )

    /**
     * 加载场景配置
     */
    fun load() {
        if (loaded) return

        try {
            val inputStream = context.resources.openRawResource(
                context.resources.getIdentifier(DEFAULT_SCENES_FILE, "raw", context.packageName)
            )
            val reader = BufferedReader(InputStreamReader(inputStream))
            val jsonStr = reader.readText()
            reader.close()

            val jsonObject = JSONObject(jsonStr)
            jsonObject.keys().forEach { sceneId ->
                val sceneObj = jsonObject.getJSONObject(sceneId)
                val config = parseSceneConfig(sceneId, sceneObj)
                scenes[sceneId] = config
            }

            loaded = true
            println("[ModelSceneRegistry] 已加载 ${scenes.size} 个场景配置")
        } catch (e: Exception) {
            System.err.println("[ModelSceneRegistry] 加载场景配置失败: ${e.message}")
        }
    }

    /**
     * 解析场景配置
     */
    private fun parseSceneConfig(sceneId: String, obj: JSONObject): SceneConfig {
        val model = obj.optString("model", "")
        val prompt = obj.optString("prompt", "")
        val transport = obj.optString("transport", "openai_compatible")
        val responseParser = obj.optString("response_parser", "text_content")
        val description = obj.optString("description", "")

        // 解析多语言 prompt
        val promptI18nObj = obj.optJSONObject("prompt_i18n")
        val promptI18n = mutableMapOf<String, String>()
        if (promptI18nObj != null) {
            promptI18nObj.keys().forEach { lang ->
                promptI18n[lang] = promptI18nObj.getString(lang)
            }
        }

        // 解析多语言 description
        val descriptionI18nObj = obj.optJSONObject("description_i18n")
        val descriptionI18n = mutableMapOf<String, String>()
        if (descriptionI18nObj != null) {
            descriptionI18nObj.keys().forEach { lang ->
                descriptionI18n[lang] = descriptionI18nObj.getString(lang)
            }
        }

        return SceneConfig(
            sceneId = sceneId,
            model = model,
            prompt = prompt,
            promptI18n = promptI18n,
            description = description,
            descriptionI18n = descriptionI18n,
            transport = transport,
            responseParser = responseParser
        )
    }

    /**
     * 获取场景配置
     *
     * @param sceneId 场景 ID（如 "scene.agent.system"）
     * @return 场景配置，如果不存在返回 null
     */
    fun getScene(sceneId: String): SceneConfig? {
        if (!loaded) load()
        return scenes[sceneId]
    }

    /**
     * 获取场景的 Prompt 模板
     *
     * @param sceneId 场景 ID
     * @param language 语言代码（如 "zh-CN", "en-US"）
     * @return Prompt 模板，如果不存在返回空字符串
     */
    fun getPrompt(sceneId: String, language: String = DEFAULT_LANGUAGE): String {
        val scene = getScene(sceneId) ?: return ""
        
        // 优先返回指定语言的 prompt
        return scene.promptI18n[language] ?: scene.prompt
    }

    /**
     * 渲染 Prompt 模板（替换 {{KEY}} 占位符）
     *
     * @param template Prompt 模板
     * @param variables 变量映射
     * @return 渲染后的 Prompt
     */
    fun renderPrompt(template: String, variables: Map<String, String>): String {
        var result = template
        variables.forEach { (key, value) ->
            result = result.replace("{{$key}}", value)
        }
        return result
    }

    /**
     * 获取并渲染场景 Prompt
     *
     * @param sceneId 场景 ID
     * @param variables 变量映射
     * @param language 语言代码
     * @return 渲染后的 Prompt
     */
    fun getRenderedPrompt(
        sceneId: String, 
        variables: Map<String, String> = emptyMap(),
        language: String = DEFAULT_LANGUAGE
    ): String {
        val template = getPrompt(sceneId, language)
        return if (variables.isEmpty()) template else renderPrompt(template, variables)
    }

    /**
     * 获取场景的模型名称
     *
     * @param sceneId 场景 ID
     * @return 模型名称，如果不存在返回空字符串
     */
    fun getModel(sceneId: String): String {
        return getScene(sceneId)?.model ?: ""
    }

    /**
     * 获取场景的描述
     *
     * @param sceneId 场景 ID
     * @param language 语言代码
     * @return 场景描述
     */
    fun getDescription(sceneId: String, language: String = DEFAULT_LANGUAGE): String {
        val scene = getScene(sceneId) ?: return ""
        return scene.descriptionI18n[language] ?: scene.description
    }

    /**
     * 获取所有场景 ID
     */
    fun getAllSceneIds(): List<String> {
        if (!loaded) load()
        return scenes.keys.toList()
    }

    /**
     * 检查场景是否存在
     */
    fun hasScene(sceneId: String): Boolean {
        if (!loaded) load()
        return scenes.containsKey(sceneId)
    }

    /**
     * 获取场景数量
     */
    fun getSceneCount(): Int {
        if (!loaded) load()
        return scenes.size
    }
}
