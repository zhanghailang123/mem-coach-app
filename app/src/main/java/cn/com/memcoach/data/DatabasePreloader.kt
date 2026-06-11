package cn.com.memcoach.data

import android.content.Context
import android.database.Cursor
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import java.io.File
import java.io.FileOutputStream

/**
 * 数据库预加载回调
 *
 * 在数据库首次创建时，从 assets 中复制预置的真题数据。
 */
class DatabasePreloader(
    private val context: Context
) : RoomDatabase.Callback() {

    override fun onCreate(db: SupportSQLiteDatabase) {
        super.onCreate(db)

        android.util.Log.i("DatabasePreloader", "数据库创建回调触发")

        // 立即在当前线程预加载（onCreate 在事务中）
        preloadExamQuestions(db)
        preloadVocabulary(db)
    }

    override fun onOpen(db: SupportSQLiteDatabase) {
        super.onOpen(db)

        // 兼容已经安装过但 exam_questions 为空或只导入了部分数据的本地库。
        preloadExamQuestions(db)
        preloadVocabulary(db)
    }

    private fun preloadExamQuestions(db: SupportSQLiteDatabase) {
        try {
            val assetDbPath = "exam_questions.db"

            android.util.Log.i("DatabasePreloader", "检查 assets 中的数据库文件...")

            normalizeExistingCode199Questions(db)

            val assetsList = context.assets.list("") ?: emptyArray()
            android.util.Log.i("DatabasePreloader", "assets 文件列表: ${assetsList.joinToString()}")

            if (!assetsList.contains(assetDbPath)) {
                android.util.Log.w("DatabasePreloader", "未找到预置数据，跳过预加载")
                return
            }

            android.util.Log.i("DatabasePreloader", "开始预加载真题数据...")

            // 复制到临时文件
            val tempFile = File(context.cacheDir, "exam_questions_temp.db")
            context.assets.open(assetDbPath).use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }

            // 打开临时数据库读取数据
            val tempDb = android.database.sqlite.SQLiteDatabase.openDatabase(
                tempFile.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY
            )

            val assetCount = tempDb.rawQuery(
                """
                SELECT COUNT(*)
                FROM exam_questions
                WHERE year IS NOT NULL
                  AND id LIKE '20__-%-q%'
                  AND subject IN ('math', 'logic', 'writing', 'management_comprehensive')
                """.trimIndent(),
                null
            ).use { cursor ->
                if (cursor.moveToFirst()) cursor.getInt(0) else 0
            }

            val existingPrebuiltCount = db.query(
                """
                SELECT COUNT(*)
                FROM exam_questions
                WHERE id LIKE '20__-%-q%'
                """.trimIndent()
            ).use { cursor ->
                if (cursor.moveToFirst()) cursor.getInt(0) else 0
            }

            if (assetCount <= 0) {
                android.util.Log.w("DatabasePreloader", "预置真题库中没有可导入的数据")
                tempDb.close()
                tempFile.delete()
                return
            }

            repairConditionSufficiencyQuestions(db, tempDb)

            if (existingPrebuiltCount >= assetCount) {
                android.util.Log.i(
                    "DatabasePreloader",
                    "预置真题已存在，跳过导入：$existingPrebuiltCount/$assetCount"
                )
                tempDb.close()
                tempFile.delete()
                return
            }

            val cursor = tempDb.rawQuery(
                """
                SELECT *
                FROM exam_questions
                WHERE year IS NOT NULL
                  AND id LIKE '20__-%-q%'
                  AND subject IN ('math', 'logic', 'writing', 'management_comprehensive')
                ORDER BY year ASC, subject ASC, question_number ASC, id ASC
                """.trimIndent(),
                null
            )
            var count = 0
            var skipped = 0

            val insertSql = """
                INSERT OR IGNORE INTO exam_questions
                (id, year, subject, section, question_number, chapter, topic, type, difficulty,
                 stem, options, answer, explanation, source_file, source_document_id, source_page,
                 knowledge_tags, source_text, source_page_type, answer_source_text, answer_source_page,
                 merge_status, stem_hash, parse_confidence, parse_status, parse_notes, exam_frequency,
                 embedding, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            while (cursor.moveToNext()) {
                val id = cursor.getStringOrNull("id")?.takeIf { it.isNotBlank() }
                val year = cursor.getIntOrNull("year")
                val rawSubject = cursor.getStringOrNull("subject")?.takeIf { it.isNotBlank() }
                val rawSection = cursor.getStringOrNull("section")?.takeIf { it.isNotBlank() }
                val stem = cursor.getStringOrNull("stem")?.takeIf { it.isNotBlank() }
                val type = cursor.getStringOrNull("type")?.takeIf { it.isNotBlank() } ?: "choice"
                val source = cursor.getStringOrNull("source_file")?.takeIf { it.isNotBlank() }
                    ?: cursor.getStringOrNull("source")?.takeIf { it.isNotBlank() }
                    ?: "预置真题库"
                val createdAt = cursor.getLongOrNull("created_at") ?: System.currentTimeMillis()
                val updatedAt = cursor.getLongOrNull("updated_at") ?: createdAt
                val subject = normalizeExamSubject(rawSubject)
                val section = normalizeExamSection(rawSection) ?: normalizeExamSection(rawSubject)

                if (id == null || year == null || subject == null || section == null || stem == null) {
                    skipped++
                    continue
                }

                val topic = cursor.getStringOrNull("topic")?.takeIf { it.isNotBlank() }
                    ?: rawSection?.takeIf { normalizeExamSection(it) == null }
                    ?: firstJsonArrayValue(cursor.getStringOrNull("knowledge_points"))
                val knowledgeTags = cursor.getStringOrNull("knowledge_tags")
                    ?.takeIf { it.isNotBlank() }
                    ?: cursor.getStringOrNull("knowledge_points")
                    ?.takeIf { it.isNotBlank() }
                    ?: cursor.getStringOrNull("tags")

                db.execSQL(insertSql, arrayOf(
                    id,
                    year,
                    subject,
                    section,
                    cursor.getIntOrNull("question_number"),
                    cursor.getStringOrNull("chapter"),
                    topic,
                    type,
                    normalizeDifficulty(cursor.getStringOrNull("difficulty")),
                    stem,
                    cursor.getStringOrNull("options"),
                    cursor.getStringOrNull("answer"),
                    cursor.getStringOrNull("explanation"),
                    source,
                    cursor.getStringOrNull("source_document_id"),
                    cursor.getIntOrNull("source_page") ?: 0,
                    knowledgeTags,
                    cursor.getStringOrNull("source_text"),
                    cursor.getStringOrNull("source_page_type") ?: "imported",
                    cursor.getStringOrNull("answer_source_text"),
                    cursor.getIntOrNull("answer_source_page"),
                    cursor.getStringOrNull("merge_status") ?: "merged",
                    cursor.getStringOrNull("stem_hash"),
                    cursor.getFloatOrNull("parse_confidence") ?: 1.0f,
                    normalizeParseStatus(cursor.getStringOrNull("parse_status")),
                    null,
                    0,
                    null,
                    createdAt,
                    updatedAt
                ))
                count++
            }
            cursor.close()
            tempDb.close()
            tempFile.delete()

            android.util.Log.i(
                "DatabasePreloader",
                "✓ 成功预加载 $count 道真题，跳过 $skipped 条无效数据"
            )

        } catch (e: Exception) {
            android.util.Log.e("DatabasePreloader", "预加载失败: ${e.message}", e)
        }
    }

    private fun repairConditionSufficiencyQuestions(
        db: SupportSQLiteDatabase,
        tempDb: android.database.sqlite.SQLiteDatabase
    ) {
        val staleCountBefore = countStaleConditionSufficiencyQuestions(db)
        if (staleCountBefore <= 0) return

        android.util.Log.i(
            "DatabasePreloader",
            "检测到 $staleCountBefore 道条件充分性题缺少条件/选项，开始从预置库修复"
        )

        tempDb.rawQuery(
            """
            SELECT id, stem, options, explanation, updated_at
            FROM exam_questions
            WHERE type = 'condition_sufficiency'
              AND id LIKE '20__-%-q%'
              AND options IS NOT NULL
              AND options != ''
              AND stem LIKE '%已知条件%'
            """.trimIndent(),
            null
        ).use { cursor ->
            val updateSql = """
                UPDATE exam_questions
                SET stem = ?,
                    options = ?,
                    explanation = CASE
                        WHEN ? IS NULL OR ? = '' THEN explanation
                        ELSE ?
                    END,
                    updated_at = ?
                WHERE id = ?
                  AND type = 'condition_sufficiency'
                  AND (
                      options IS NULL
                      OR options = ''
                      OR stem NOT LIKE '%已知条件%'
                  )
            """.trimIndent()

            while (cursor.moveToNext()) {
                val id = cursor.getStringOrNull("id") ?: continue
                val stem = cursor.getStringOrNull("stem") ?: continue
                val options = cursor.getStringOrNull("options") ?: continue
                val explanation = cursor.getStringOrNull("explanation")
                val updatedAt = cursor.getLongOrNull("updated_at") ?: System.currentTimeMillis()

                db.execSQL(updateSql, arrayOf(
                    stem,
                    options,
                    explanation,
                    explanation,
                    explanation,
                    updatedAt,
                    id
                ))
            }
        }

        val staleCountAfter = countStaleConditionSufficiencyQuestions(db)
        android.util.Log.i(
            "DatabasePreloader",
            "条件充分性题修复完成：${staleCountBefore - staleCountAfter}/$staleCountBefore"
        )
    }

    private fun countStaleConditionSufficiencyQuestions(db: SupportSQLiteDatabase): Int {
        return db.query(
            """
            SELECT COUNT(*)
            FROM exam_questions
            WHERE type = 'condition_sufficiency'
              AND (
                  options IS NULL
                  OR options = ''
                  OR stem NOT LIKE '%已知条件%'
              )
            """.trimIndent()
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }
    }

    private fun normalizeExistingCode199Questions(db: SupportSQLiteDatabase) {
        db.execSQL("DELETE FROM exam_questions WHERE id = '2025真题'")

        db.execSQL("""
            UPDATE exam_questions
            SET topic = CASE
                    WHEN (topic IS NULL OR topic = '')
                         AND section IS NOT NULL
                         AND section NOT IN ('math', 'logic', 'writing', 'english')
                    THEN section
                    ELSE topic
                END,
                section = CASE subject
                    WHEN 'math' THEN 'math'
                    WHEN '数学' THEN 'math'
                    WHEN 'logic' THEN 'logic'
                    WHEN '逻辑' THEN 'logic'
                    WHEN 'writing' THEN 'writing'
                    WHEN '写作' THEN 'writing'
                    ELSE section
                END,
                subject = 'management_comprehensive',
                parse_status = CASE
                    WHEN parse_status IS NULL OR parse_status = '' OR parse_status = 'imported'
                    THEN 'parsed'
                    ELSE parse_status
                END
            WHERE subject IN ('math', '数学', 'logic', '逻辑', 'writing', '写作')
        """.trimIndent())

        db.execSQL("""
            UPDATE exam_questions
            SET parse_status = 'parsed'
            WHERE parse_status IS NULL OR parse_status = '' OR parse_status = 'imported'
        """.trimIndent())
    }

    private fun Cursor.getStringOrNull(columnName: String): String? {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getString(index) else null
    }

    private fun Cursor.getIntOrNull(columnName: String): Int? {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getInt(index) else null
    }

    private fun Cursor.getLongOrNull(columnName: String): Long? {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getLong(index) else null
    }

    private fun Cursor.getFloatOrNull(columnName: String): Float? {
        val index = getColumnIndex(columnName)
        return if (index >= 0 && !isNull(index)) getFloat(index) else null
    }

    private fun Cursor.getLongOrNull(columnIndex: Int): Long? {
        return if (columnIndex >= 0 && columnIndex < columnCount && !isNull(columnIndex)) getLong(columnIndex) else null
    }

    private fun normalizeDifficulty(raw: String?): String? {
        return when (raw?.trim()) {
            null, "" -> null
            "1" -> "basic"
            "2", "3" -> "medium"
            "4", "5" -> "hard"
            else -> raw.trim()
        }
    }

    private fun normalizeParseStatus(raw: String?): String {
        return when (raw?.trim()?.lowercase()) {
            "parsed", "needs_review", "invalid" -> raw.trim().lowercase()
            else -> "parsed"
        }
    }

    private fun normalizeExamSubject(raw: String?): String? {
        return when (raw?.trim()?.lowercase()) {
            null, "", "null" -> null
            "math", "logic", "writing", "数学", "逻辑", "写作",
            "management_comprehensive", "management", "comprehensive", "管综", "管理类综合", "管理类综合能力" -> "management_comprehensive"
            "english", "english2", "english_ii", "英语", "英语二" -> "english"
            else -> raw.trim()
        }
    }

    private fun normalizeExamSection(raw: String?): String? {
        return when (raw?.trim()?.lowercase()) {
            null, "", "null", "all", "全部" -> null
            "math", "数学" -> "math"
            "logic", "逻辑" -> "logic"
            "writing", "写作" -> "writing"
            "english", "英语", "english2", "english_ii", "英语二" -> "english"
            "cloze" -> "cloze"
            "reading_a", "reading-a", "阅读理解a" -> "reading_a"
            "reading_b", "reading-b", "阅读理解b" -> "reading_b"
            "translation", "翻译" -> "translation"
            "writing_a", "writing-a", "小作文" -> "writing_a"
            "writing_b", "writing-b", "大作文" -> "writing_b"
            else -> null
        }
    }

    private fun firstJsonArrayValue(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        return try {
            val array = org.json.JSONArray(raw)
            if (array.length() > 0) array.optString(0).takeIf { it.isNotBlank() } else null
        } catch (_: Exception) {
            raw.trim().takeIf { it.isNotBlank() }
        }
    }

    private fun preloadVocabulary(db: SupportSQLiteDatabase) {
        try {
            val assetDbPath = "vocabulary.db"
            val assetsList = context.assets.list("") ?: emptyArray()
            if (!assetsList.contains(assetDbPath)) return

            val existingCount = db.query("SELECT COUNT(*) FROM vocabulary").use { c ->
                if (c.moveToFirst()) c.getInt(0) else 0
            }
            if (existingCount > 0) return

            val tempFile = File(context.cacheDir, "vocabulary_temp.db")
            context.assets.open(assetDbPath).use { input ->
                FileOutputStream(tempFile).use { it.write(input.readBytes()) }
            }

            val tempDb = android.database.sqlite.SQLiteDatabase.openDatabase(
                tempFile.absolutePath, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY
            )

            tempDb.rawQuery("SELECT * FROM vocabulary", null).use { cursor ->
                var count = 0
                while (cursor.moveToNext()) {
                    db.execSQL("INSERT OR IGNORE INTO vocabulary VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", arrayOf(
                        cursor.getString(0), cursor.getString(1), cursor.getString(2),
                        cursor.getString(3), cursor.getString(4), cursor.getString(5),
                        cursor.getString(6), cursor.getString(7), cursor.getString(8),
                        cursor.getInt(9), cursor.getLongOrNull(10), cursor.getLongOrNull(11),
                        cursor.getLong(12), cursor.getLong(13)
                    ))
                    count++
                }
                android.util.Log.i("DatabasePreloader", "✓ 预加载 $count 个单词")
            }
            tempDb.close()
            tempFile.delete()
        } catch (e: Exception) {
            android.util.Log.e("DatabasePreloader", "单词预加载失败", e)
        }
    }
}
