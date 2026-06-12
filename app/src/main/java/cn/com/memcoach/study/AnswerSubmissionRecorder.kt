package cn.com.memcoach.study

import cn.com.memcoach.data.dao.AnswerRecordDao
import cn.com.memcoach.data.dao.ExamQuestionDao
import cn.com.memcoach.data.dao.KnowledgeNodeDao
import cn.com.memcoach.data.dao.StudyRecordDao
import cn.com.memcoach.data.dao.UserMasteryDao
import cn.com.memcoach.data.entity.AnswerRecord
import cn.com.memcoach.data.entity.StudyRecord
import cn.com.memcoach.data.entity.UserMastery
import java.util.Locale

data class AnswerSubmissionResult(
    val correct: Boolean,
    val userAnswer: String,
    val correctAnswer: String,
    val explanation: String,
    val hint: String,
    val masteryLevel: String?,
    val knowledgeId: String?
)

/**
 * 统一答题记录入口：错题本、练习统计、知识点掌握度必须一起更新。
 */
class AnswerSubmissionRecorder(
    private val answerRecordDao: AnswerRecordDao,
    private val studyRecordDao: StudyRecordDao,
    private val userMasteryDao: UserMasteryDao,
    private val knowledgeNodeDao: KnowledgeNodeDao,
    private val examQuestionDao: ExamQuestionDao
) {
    suspend fun submit(
        questionId: String,
        userAnswer: String,
        correctAnswerOverride: String? = null,
        isCorrectOverride: Boolean? = null,
        timeSpentSeconds: Int = 0,
        studyMode: String = StudyRecord.MODE_PRACTICE
    ): AnswerSubmissionResult {
        val question = examQuestionDao.getById(questionId)
            ?: throw IllegalArgumentException("question not found: $questionId")
        val correctAnswer = correctAnswerOverride
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: question.answer.orEmpty()
        val isCorrect = isCorrectOverride
            ?: answersEqual(userAnswer, correctAnswer)
        val now = System.currentTimeMillis()

        answerRecordDao.insert(
            AnswerRecord(
                questionId = questionId,
                userAnswer = userAnswer,
                correctAnswer = correctAnswer,
                isCorrect = isCorrect,
                timeSpent = timeSpentSeconds,
                createdAt = now
            )
        )

        val matchedKnowledgeId = resolveKnowledgeId(
            topic = question.topic,
            subject = question.subject,
            section = question.section
        )

        studyRecordDao.insert(
            StudyRecord(
                questionId = questionId,
                userAnswer = userAnswer,
                isCorrect = isCorrect,
                timeSpentSeconds = timeSpentSeconds,
                studyMode = studyMode,
                knowledgeId = matchedKnowledgeId ?: question.topic?.trim()?.takeIf { it.isNotBlank() },
                createdAt = now
            )
        )

        val masteryLevel = matchedKnowledgeId?.let {
            updateMastery(
                knowledgeId = it,
                correct = isCorrect,
                now = now
            )
        }

        return AnswerSubmissionResult(
            correct = isCorrect,
            userAnswer = userAnswer,
            correctAnswer = correctAnswer,
            explanation = question.explanation.orEmpty(),
            hint = if (isCorrect) "回答正确！继续保持" else "请仔细阅读解析，理解错误原因后再尝试变式练习",
            masteryLevel = masteryLevel,
            knowledgeId = matchedKnowledgeId
        )
    }

    private suspend fun resolveKnowledgeId(
        topic: String?,
        subject: String?,
        section: String?
    ): String? {
        val rawTopic = topic?.trim()?.takeIf { it.isNotBlank() } ?: return null
        knowledgeNodeDao.getById(rawTopic)?.let { return it.id }

        val candidates = knowledgeNodeDao.searchByName(rawTopic, limit = 10)
        if (candidates.isEmpty()) return null

        val expectedSubjects = expectedKnowledgeSubjects(subject, section)
        return candidates.firstOrNull { node ->
            node.subject in expectedSubjects || node.name == rawTopic
        }?.id ?: candidates.first().id
    }

    private fun expectedKnowledgeSubjects(subject: String?, section: String?): Set<String> {
        val result = linkedSetOf<String>()
        normalizeKnowledgeSubject(section)?.let { result.add(it) }
        normalizeKnowledgeSubject(subject)?.let { result.add(it) }
        if (subject == "management_comprehensive") {
            result.addAll(listOf("math", "logic", "writing"))
        }
        return result
    }

    private fun normalizeKnowledgeSubject(value: String?): String? {
        return when (value?.trim()?.lowercase(Locale.US)) {
            null, "", "all", "null" -> null
            "management_comprehensive", "management", "comprehensive", "管综", "管理类综合", "管理类综合能力" -> null
            "math", "数学" -> "math"
            "logic", "逻辑" -> "logic"
            "writing", "写作" -> "writing"
            "english", "english2", "english_ii", "英语", "英语二" -> "english"
            else -> value.trim()
        }
    }

    private suspend fun updateMastery(
        knowledgeId: String,
        correct: Boolean,
        now: Long
    ): String {
        val existing = userMasteryDao.getByUserAndKnowledge(
            userId = "default",
            knowledgeId = knowledgeId
        )
        val updated = if (existing != null) {
            val newLevel = if (correct) {
                minOf(1f, existing.masteryLevel + 0.1f)
            } else {
                maxOf(0f, existing.masteryLevel - 0.05f)
            }
            val nextReview = if (correct) {
                now + (existing.reviewCount + 1) * 24 * 60 * 60 * 1000L
            } else {
                now + 12 * 60 * 60 * 1000L
            }
            existing.copy(
                masteryLevel = newLevel,
                reviewCount = existing.reviewCount + 1,
                correctCount = if (correct) existing.correctCount + 1 else existing.correctCount,
                lastReviewDate = now,
                nextReviewDate = nextReview,
                updatedAt = now
            )
        } else {
            UserMastery(
                userId = "default",
                knowledgeId = knowledgeId,
                masteryLevel = if (correct) 0.5f else 0.2f,
                reviewCount = 1,
                correctCount = if (correct) 1 else 0,
                lastReviewDate = now,
                nextReviewDate = if (correct) now + 24 * 60 * 60 * 1000L else now + 12 * 60 * 60 * 1000L,
                updatedAt = now
            )
        }
        userMasteryDao.upsert(updated)
        return "%.0f%%".format(updated.masteryLevel * 100)
    }

    private fun answersEqual(userAnswer: String, correctAnswer: String): Boolean {
        return normalizeAnswer(userAnswer) == normalizeAnswer(correctAnswer)
    }

    private fun normalizeAnswer(answer: String): String {
        return answer
            .trim()
            .uppercase(Locale.US)
            .replace(Regex("[\\s，,。．.、:：;；]"), "")
    }
}
