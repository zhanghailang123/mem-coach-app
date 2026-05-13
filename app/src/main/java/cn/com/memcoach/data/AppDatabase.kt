package cn.com.memcoach.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import cn.com.memcoach.data.dao.*
import cn.com.memcoach.data.entity.*

/**
 * MEM Coach 主数据库
 *
 * 使用 Room 持久化框架，包含 4 张核心表：
 * - exam_questions：真题
 * - knowledge_nodes / knowledge_edges：知识图谱
 * - user_mastery：用户掌握度
 * - study_records：学习记录
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
        StudyRecord::class
    ],
    version = 1,
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

    companion object {
        private const val DATABASE_NAME = "mem_coach.db"

        @Volatile
        private var INSTANCE: AppDatabase? = null

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
                // MVP 阶段使用 destructive migration，开发中重建数据库
                // 正式发布后改用 Migration 策略
                .fallbackToDestructiveMigration()
                .build()
        }
    }
}
