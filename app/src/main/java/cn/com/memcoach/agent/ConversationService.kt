package cn.com.memcoach.agent

import cn.com.memcoach.data.dao.ConversationDao
import cn.com.memcoach.data.dao.ChatMessageDao
import cn.com.memcoach.data.entity.ConversationEntity
import cn.com.memcoach.data.entity.ChatMessageEntity

/**
 * 会话管理服务
 *
 * 提供会话和消息的 CRUD 操作，支持会话列表、消息加载、流式更新等功能。
 * 作为 ChatSheet 和数据库之间的中间层，封装业务逻辑。
 */
class ConversationService(
    private val conversationDao: ConversationDao,
    private val chatMessageDao: ChatMessageDao
) {
    /**
     * 创建新会话
     *
     * @param title 会话标题，默认为"新对话"
     * @param userId 用户 ID
     * @return 新创建的会话实体
     */
    suspend fun createConversation(
        title: String = "新对话",
        userId: String = "default"
    ): ConversationEntity {
        val conversation = ConversationEntity(
            userId = userId,
            title = title,
            createdAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis()
        )
        val id = conversationDao.insert(conversation)
        return conversation.copy(id = id)
    }

    /**
     * 获取用户的所有会话
     *
     * @param userId 用户 ID
     * @return 会话列表，按更新时间倒序
     */
    suspend fun getConversations(userId: String = "default"): List<ConversationEntity> {
        return conversationDao.getAllByUser(userId)
    }

    /**
     * 分页获取用户会话
     *
     * @param userId 用户 ID
     * @param limit 每页数量
     * @param offset 偏移量
     * @return 会话列表
     */
    suspend fun getConversationsPaginated(
        userId: String = "default",
        limit: Int = 20,
        offset: Int = 0
    ): List<ConversationEntity> {
        return conversationDao.getByUserPaginated(userId, limit, offset)
    }

    /**
     * 根据 ID 获取会话
     *
     * @param conversationId 会话 ID
     * @return 会话实体，如果不存在则返回 null
     */
    suspend fun getConversation(conversationId: Long): ConversationEntity? {
        return conversationDao.getById(conversationId)
    }

    /**
     * 更新会话标题
     *
     * @param conversationId 会话 ID
     * @param title 新标题
     */
    suspend fun updateConversationTitle(conversationId: Long, title: String) {
        conversationDao.updateTitle(conversationId, title)
    }

    /**
     * 更新会话摘要
     *
     * @param conversationId 会话 ID
     * @param summary 新摘要
     */
    suspend fun updateConversationSummary(conversationId: Long, summary: String?) {
        conversationDao.updateSummary(conversationId, summary)
    }

    /**
     * 软删除会话
     *
     * @param conversationId 会话 ID
     */
    suspend fun deleteConversation(conversationId: Long) {
        conversationDao.softDelete(conversationId)
    }

    /**
     * 硬删除会话及其所有消息
     *
     * @param conversationId 会话 ID
     */
    suspend fun deleteConversationWithMessages(conversationId: Long) {
        chatMessageDao.deleteByConversationId(conversationId)
        conversationDao.delete(conversationId)
    }

    /**
     * 添加用户消息
     *
     * @param conversationId 会话 ID
     * @param content 消息内容
     * @return 新创建的消息实体
     */
    suspend fun addUserMessage(
        conversationId: Long,
        content: String
    ): ChatMessageEntity {
        val message = ChatMessageEntity(
            conversationId = conversationId,
            role = ChatMessageEntity.ROLE_USER,
            content = content,
            createdAt = System.currentTimeMillis()
        )
        val id = chatMessageDao.insert(message)
        updateConversationTimestamp(conversationId)
        return message.copy(id = id)
    }

    /**
     * 添加助手消息
     *
     * @param conversationId 会话 ID
     * @param content 消息内容
     * @param isStreaming 是否正在流式生成
     * @return 新创建的消息实体
     */
    suspend fun addAssistantMessage(
        conversationId: Long,
        content: String,
        isStreaming: Boolean = false
    ): ChatMessageEntity {
        val message = ChatMessageEntity(
            conversationId = conversationId,
            role = ChatMessageEntity.ROLE_ASSISTANT,
            content = content,
            isStreaming = isStreaming,
            createdAt = System.currentTimeMillis()
        )
        val id = chatMessageDao.insert(message)
        updateConversationTimestamp(conversationId)
        return message.copy(id = id)
    }

    /**
     * 添加系统消息
     *
     * @param conversationId 会话 ID
     * @param content 消息内容
     * @return 新创建的消息实体
     */
    suspend fun addSystemMessage(
        conversationId: Long,
        content: String
    ): ChatMessageEntity {
        val message = ChatMessageEntity(
            conversationId = conversationId,
            role = ChatMessageEntity.ROLE_SYSTEM,
            content = content,
            createdAt = System.currentTimeMillis()
        )
        val id = chatMessageDao.insert(message)
        updateConversationTimestamp(conversationId)
        return message.copy(id = id)
    }

    /**
     * 添加工具调用消息
     *
     * @param conversationId 会话 ID
     * @param toolName 工具名称
     * @param status 工具状态
     * @param result 工具结果
     * @return 新创建的消息实体
     */
    suspend fun addToolMessage(
        conversationId: Long,
        toolName: String,
        status: String = ChatMessageEntity.TOOL_STATUS_RUNNING,
        result: String? = null
    ): ChatMessageEntity {
        val message = ChatMessageEntity(
            conversationId = conversationId,
            role = ChatMessageEntity.ROLE_TOOL,
            content = "工具调用: $toolName",
            toolName = toolName,
            toolStatus = status,
            toolResult = result,
            createdAt = System.currentTimeMillis()
        )
        val id = chatMessageDao.insert(message)
        updateConversationTimestamp(conversationId)
        return message.copy(id = id)
    }

    /**
     * 更新消息内容（用于流式更新）
     *
     * @param messageId 消息 ID
     * @param content 新内容
     */
    suspend fun updateMessageContent(messageId: Long, content: String) {
        chatMessageDao.updateContent(messageId, content)
    }

    /**
     * 更新消息的流式状态
     *
     * @param messageId 消息 ID
     * @param isStreaming 是否正在流式生成
     */
    suspend fun updateMessageStreamingStatus(messageId: Long, isStreaming: Boolean) {
        chatMessageDao.updateStreamingStatus(messageId, isStreaming)
    }

    /**
     * 更新工具调用状态
     *
     * @param messageId 消息 ID
     * @param status 新状态
     * @param result 工具结果
     */
    suspend fun updateToolStatus(
        messageId: Long,
        status: String,
        result: String?
    ) {
        chatMessageDao.updateToolStatus(messageId, status, result)
    }

    /**
     * 更新深度思考内容
     *
     * @param messageId 消息 ID
     * @param content 思考内容
     * @param stage 思考阶段
     */
    suspend fun updateThinkingContent(
        messageId: Long,
        content: String,
        stage: Int?
    ) {
        chatMessageDao.updateThinkingContent(messageId, content, stage)
    }

    /**
     * 获取会话的所有消息
     *
     * @param conversationId 会话 ID
     * @return 消息列表，按创建时间正序
     */
    suspend fun getMessages(conversationId: Long): List<ChatMessageEntity> {
        return chatMessageDao.getByConversationId(conversationId)
    }

    /**
     * 分页获取会话消息
     *
     * @param conversationId 会话 ID
     * @param limit 每页数量
     * @param offset 偏移量
     * @return 消息列表
     */
    suspend fun getMessagesPaginated(
        conversationId: Long,
        limit: Int = 50,
        offset: Int = 0
    ): List<ChatMessageEntity> {
        return chatMessageDao.getByConversationIdPaginated(conversationId, limit, offset)
    }

    /**
     * 获取会话的最新 N 条消息
     *
     * @param conversationId 会话 ID
     * @param limit 消息数量
     * @return 消息列表
     */
    suspend fun getLatestMessages(
        conversationId: Long,
        limit: Int = 20
    ): List<ChatMessageEntity> {
        return chatMessageDao.getLatestByConversationId(conversationId, limit)
    }

    /**
     * 获取会话的最后一条助手消息
     *
     * @param conversationId 会话 ID
     * @return 消息实体，如果不存在则返回 null
     */
    suspend fun getLastAssistantMessage(conversationId: Long): ChatMessageEntity? {
        return chatMessageDao.getLastAssistantMessage(conversationId)
    }

    /**
     * 获取会话的最后一条用户消息
     *
     * @param conversationId 会话 ID
     * @return 消息实体，如果不存在则返回 null
     */
    suspend fun getLastUserMessage(conversationId: Long): ChatMessageEntity? {
        return chatMessageDao.getLastUserMessage(conversationId)
    }

    /**
     * 获取会话的消息数量
     *
     * @param conversationId 会话 ID
     * @return 消息数量
     */
    suspend fun getMessageCount(conversationId: Long): Int {
        return chatMessageDao.getCountByConversationId(conversationId)
    }

    /**
     * 获取会话的总 token 数量
     *
     * @param conversationId 会话 ID
     * @return token 数量
     */
    suspend fun getTotalTokenCount(conversationId: Long): Int {
        return chatMessageDao.getTotalTokenCount(conversationId) ?: 0
    }

    /**
     * 搜索消息内容
     *
     * @param conversationId 会话 ID
     * @param query 搜索关键词
     * @param limit 结果数量限制
     * @return 匹配的消息列表
     */
    suspend fun searchMessages(
        conversationId: Long,
        query: String,
        limit: Int = 10
    ): List<ChatMessageEntity> {
        return chatMessageDao.searchByContent(conversationId, query, limit)
    }

    /**
     * 删除消息
     *
     * @param messageId 消息 ID
     */
    suspend fun deleteMessage(messageId: Long) {
        chatMessageDao.deleteById(messageId)
    }

    /**
     * 删除会话的所有消息
     *
     * @param conversationId 会话 ID
     */
    suspend fun deleteAllMessages(conversationId: Long) {
        chatMessageDao.deleteByConversationId(conversationId)
    }

    /**
     * 更新会话的最后更新时间
     *
     * @param conversationId 会话 ID
     */
    private suspend fun updateConversationTimestamp(conversationId: Long) {
        conversationDao.updateTimestamp(conversationId)
    }

    /**
     * 更新会话的消息数量
     *
     * @param conversationId 会话 ID
     */
    suspend fun updateConversationMessageCount(conversationId: Long) {
        val count = chatMessageDao.getCountByConversationId(conversationId)
        conversationDao.updateMessageCount(conversationId, count)
    }

    /**
     * 生成会话摘要（基于最新消息）
     *
     * @param conversationId 会话 ID
     * @param maxLength 最大长度
     * @return 摘要文本
     */
    suspend fun generateConversationSummary(
        conversationId: Long,
        maxLength: Int = 100
    ): String {
        val lastUserMessage = chatMessageDao.getLastUserMessage(conversationId)
        val lastAssistantMessage = chatMessageDao.getLastAssistantMessage(conversationId)
        
        val summary = buildString {
            if (lastUserMessage != null) {
                append("用户: ${lastUserMessage.content.take(50)}")
            }
            if (lastAssistantMessage != null) {
                if (isNotEmpty()) append(" | ")
                append("AI: ${lastAssistantMessage.content.take(50)}")
            }
        }
        
        return if (summary.length > maxLength) {
            summary.take(maxLength) + "..."
        } else {
            summary
        }
    }

    /**
     * 自动更新会话标题（基于第一条用户消息）
     *
     * @param conversationId 会话 ID
     */
    suspend fun autoUpdateConversationTitle(conversationId: Long) {
        val firstUserMessage = chatMessageDao.getLastUserMessage(conversationId)
        if (firstUserMessage != null) {
            val title = firstUserMessage.content.take(20).let {
                if (it.length == 20) "$it..." else it
            }
            conversationDao.updateTitle(conversationId, title)
        }
    }
}