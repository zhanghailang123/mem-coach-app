package cn.com.memcoach.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 单词实体
 */
@Entity(
    tableName = "vocabulary",
    indices = [
        Index(value = ["word"], name = "idx_vocab_word"),
        Index(value = ["status"], name = "idx_vocab_status"),
        Index(value = ["next_review_at"], name = "idx_vocab_next_review")
    ]
)
data class Vocabulary(
    @PrimaryKey
    val id: String, // vocab-adapt

    val word: String, // adapt

    @ColumnInfo(name = "phonetic")
    val phonetic: String? = null, // /əˈdæpt/

    @ColumnInfo(name = "definitions")
    val definitions: String, // JSON: [{part: "v.", translation: "适应", text: "..."}]

    @ColumnInfo(name = "synonyms")
    val synonyms: String? = null, // JSON: [{word: "adjust", meaning: "调整"}]

    @ColumnInfo(name = "confusables")
    val confusables: String? = null, // JSON: [{word: "adopt", meaning: "采纳"}]

    @ColumnInfo(name = "tags")
    val tags: String? = null, // JSON: ["核心词汇", "高频"]

    @ColumnInfo(name = "explanation")
    val explanation: String, // Markdown正文

    @ColumnInfo(name = "status", defaultValue = "'new'")
    val status: String = "new", // new/learning/mastered

    @ColumnInfo(name = "review_count", defaultValue = "0")
    val reviewCount: Int = 0,

    @ColumnInfo(name = "last_review_at")
    val lastReviewAt: Long? = null,

    @ColumnInfo(name = "next_review_at")
    val nextReviewAt: Long? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
)

/**
 * 单词复习记录
 */
@Entity(
    tableName = "vocabulary_reviews",
    foreignKeys = [
        ForeignKey(
            entity = Vocabulary::class,
            parentColumns = ["id"],
            childColumns = ["vocab_id"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class VocabularyReview(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    @ColumnInfo(name = "vocab_id")
    val vocabId: String,

    @ColumnInfo(name = "is_correct")
    val isCorrect: Boolean,

    @ColumnInfo(name = "review_type")
    val reviewType: String, // recognition/spelling/usage

    @ColumnInfo(name = "time_spent", defaultValue = "0")
    val timeSpent: Int = 0, // 秒

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
