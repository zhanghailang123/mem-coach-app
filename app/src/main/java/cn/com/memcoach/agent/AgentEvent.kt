package cn.com.memcoach.agent

/**
 * Agent 事件 —— 编排器向 Flutter UI 推送的 SSE 事件流
 *
 * 事件类型设计原则：
 * - ThinkingStart/Update: 展示 Agent 思考过程（推理链可视化）
 * - ToolCallStart/Complete/Error: 展示工具调用状态（增强信任）
 * - ChatMessage: 展示最终回复或中间消息
 * - ReflectionCheck: Self-Reflection 检查点
 * - Complete/Error: 终止事件
 */
sealed class AgentEvent {
    /** 思考开始（新一轮推理） */
    data class ThinkingStart(val round: Int) : AgentEvent()

    /** 思考内容流式更新 */
    data class ThinkingUpdate(val content: String) : AgentEvent()

    /** 工具调用开始 */
    data class ToolCallStart(val toolName: String, val arguments: String) : AgentEvent()

    /** 工具调用完成 */
    data class ToolCallComplete(val toolName: String, val result: String) : AgentEvent()

    /** 工具调用失败 */
    data class ToolCallError(val toolName: String, val error: String) : AgentEvent()

    /** 聊天消息（最终回复或中间输出） */
    data class ChatMessage(val content: String, val isFinal: Boolean = false) : AgentEvent()

    /** Self-Reflection 检查点触发 */
    data class ReflectionCheck(val round: Int) : AgentEvent()

    /** Agent 执行完成 */
    data class Complete(val result: AgentResult) : AgentEvent()

    /** 错误 */
    data class Error(val message: String) : AgentEvent()
}
