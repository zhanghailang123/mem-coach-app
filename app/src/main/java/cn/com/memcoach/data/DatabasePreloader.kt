package cn.com.memcoach.data

import android.content.Context
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
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

        // 异步预加载数据
        CoroutineScope(Dispatchers.IO).launch {
            preloadExamQuestions(db)
        }
    }

    private fun preloadExamQuestions(db: SupportSQLiteDatabase) {
        try {
            val assetDbPath = "exam_questions.db"

            // 检查 assets 中是否有预置数据库
            if (!context.assets.list("")?.contains(assetDbPath)!!) {
                android.util.Log.i("DatabasePreloader", "未找到预置数据，跳过预加载")
                return
            }

            android.util.Log.i("DatabasePreloader", "开始预加载真题数据...")

            // 读取预置数据库
            context.assets.open(assetDbPath).use { input ->
                // 临时文件
                val tempFile = File(context.cacheDir, "exam_questions_temp.db")
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }

                // 附加临时数据库
                db.execSQL("ATTACH DATABASE '${tempFile.absolutePath}' AS preload")

                // 复制数据
                db.execSQL("""
                    INSERT OR IGNORE INTO exam_questions
                    SELECT * FROM preload.exam_questions
                """)

                // 分离数据库
                db.execSQL("DETACH DATABASE preload")

                // 删除临时文件
                tempFile.delete()

                // 查询导入数量
                val cursor = db.query("SELECT COUNT(*) FROM exam_questions")
                if (cursor.moveToFirst()) {
                    val count = cursor.getInt(0)
                    android.util.Log.i("DatabasePreloader", "✓ 成功预加载 $count 道真题")
                }
                cursor.close()
            }
        } catch (e: Exception) {
            android.util.Log.e("DatabasePreloader", "预加载失败: ${e.message}", e)
        }
    }
}
