package cn.com.memcoach.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import cn.com.memcoach.data.dao.*
import cn.com.memcoach.data.entity.*

/**
 * MEM Coach 主数据库
 *
 * 使用 Room 持久化框架，包含 7 张核心表：
 * - exam_questions：真题
 * - knowledge_nodes / knowledge_edges：知识图谱
 * - user_mastery：用户掌握度
 * - study_records：学习记录
 * - pdf_documents：PDF 文档元数据
 * - conversations：聊天会话（v3 新增）
 * - chat_messages：聊天消息（v3 新增）
 *
 * 数据库文件位于：{context.filesDir}/databases/mem_coach.db
 * 版本号从 1 开始，后续通过 Migration 升级。
 */
@Database(
    entities = [
        ExamQuestion::class,
        KnowledgeNode::class,
        KnowledgeEdge::class,
        UserMastery::class,
        StudyRecord::class,
        PdfDocument::class,
        ConversationEntity::class,
        ChatMessageEntity::class
    ],
    version = 5,

    exportSchema = false  // MVP 阶段不导出 schema，后续可开启
)
abstract class AppDatabase : RoomDatabase() {

    /** 真题 DAO */
    abstract fun examQuestionDao(): ExamQuestionDao

    /** 知识点 DAO */
    abstract fun knowledgeNodeDao(): KnowledgeNodeDao

    /** 知识关系边 DAO */
    abstract fun knowledgeEdgeDao(): KnowledgeEdgeDao

    /** 掌握度 DAO */
    abstract fun userMasteryDao(): UserMasteryDao

    /** 学习记录 DAO */
    abstract fun studyRecordDao(): StudyRecordDao

    /** PDF 文档 DAO */
    abstract fun pdfDocumentDao(): PdfDocumentDao

    /** 会话 DAO */
    abstract fun conversationDao(): ConversationDao

    /** 聊天消息 DAO */
    abstract fun chatMessageDao(): ChatMessageDao

    companion object {
        private const val DATABASE_NAME = "mem_coach.db"

        @Volatile
        private var INSTANCE: AppDatabase? = null

        /**
         * 从版本 2 升级到版本 3 的 Migration
         * 
         * 新增会话表和聊天消息表，支持聊天记录持久化。
         */
        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(database: SupportSQLiteDatabase) {
                // 创建会话表
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS `conversations` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `user_id` TEXT NOT NULL DEFAULT 'default',
                        `title` TEXT NOT NULL DEFAULT '新对话',
                        `summary` TEXT,
                        `message_count` INTEGER NOT NULL DEFAULT 0,
                        `is_active` INTEGER NOT NULL DEFAULT 1,
                        `created_at` INTEGER NOT NULL,
                        `updated_at` INTEGER NOT NULL
                    )
                """)
                
                // 创建会话表索引
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_conversations_user_id` ON `conversations` (`user_id`)")
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_conversations_created_at` ON `conversations` (`created_at`)")
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_conversations_updated_at` ON `conversations` (`updated_at`)")
                
                // 创建聊天消息表
                database.execSQL("""
                    CREATE TABLE IF NOT EXISTS `chat_messages` (
                        `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `conversation_id` INTEGER NOT NULL,
                        `role` TEXT NOT NULL,
                        `content` TEXT NOT NULL,
                        `tool_name` TEXT,
                        `tool_result` TEXT,
                        `tool_status` TEXT,
                        `thinking_content` TEXT,
                        `thinking_stage` INTEGER,
                        `is_streaming` INTEGER NOT NULL DEFAULT 0,
                        `token_count` INTEGER NOT NULL DEFAULT 0,
                        `created_at` INTEGER NOT NULL,
                        FOREIGN KEY(`conversation_id`) REFERENCES `conversations`(`id`) ON DELETE CASCADE
                    )
                """)
                
                // 创建聊天消息表索引
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_chat_messages_conversation_id` ON `chat_messages` (`conversation_id`)")
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_chat_messages_role` ON `chat_messages` (`role`)")
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_chat_messages_created_at` ON `chat_messages` (`created_at`)")
            }
        }

        /**
         * 从版本 3 升级到版本 4 的 Migration。
         *
         * 为聊天消息补充 OpenAI function calling 历史恢复所需字段。
         */
        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE `chat_messages` ADD COLUMN `tool_call_id` TEXT")
                database.execSQL("ALTER TABLE `chat_messages` ADD COLUMN `tool_calls_json` TEXT")
            }
        }

        /**
         * 从版本 4 升级到版本 5 的 Migration。
         *
         * 为 PDF 题目解析补充质量控制和来源追溯字段。
         */
        private val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL("ALTER TABLE `exam_questions` ADD COLUMN `source_text` TEXT")
                database.execSQL("ALTER TABLE `exam_questions` ADD COLUMN `stem_hash` TEXT")
                database.execSQL("ALTER TABLE `exam_questions` ADD COLUMN `parse_confidence` REAL NOT NULL DEFAULT 0.5")
                database.execSQL("ALTER TABLE `exam_questions` ADD COLUMN `parse_status` TEXT NOT NULL DEFAULT 'parsed'")
                database.execSQL("ALTER TABLE `exam_questions` ADD COLUMN `parse_notes` TEXT")
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_exam_questions_stem_hash` ON `exam_questions` (`stem_hash`)")
                database.execSQL("CREATE INDEX IF NOT EXISTS `index_exam_questions_parse_status` ON `exam_questions` (`parse_status`)")
            }
        }

        /**
         * 获取数据库单例

         *
         * @param context Application Context
         * @return AppDatabase 实例
         */
        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: buildDatabase(context).also { INSTANCE = it }
            }
        }

        private fun buildDatabase(context: Context): AppDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                AppDatabase::class.java,
                DATABASE_NAME
            )
                .addMigrations(MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5)

                // MVP 阶段使用 destructive migration 作为兜底，开发中重建数据库
                // 正式发布后改用 Migration 策略
                .fallbackToDestructiveMigration()
                .build()
        }
    }
}
