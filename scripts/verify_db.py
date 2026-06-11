import sqlite3
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

db_path = "app/src/main/assets/exam_questions.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("=" * 60)
print("数据库验证报告")
print("=" * 60)

# 按年份和科目统计
cursor.execute("""
    SELECT year, subject, COUNT(*)
    FROM exam_questions
    GROUP BY year, subject
    ORDER BY year, subject
""")

print("\n按年份和科目统计:")
print(f"{'年份':<8} {'科目':<10} {'题数':<6}")
print("-" * 30)
for row in cursor.fetchall():
    year = row[0] if row[0] else "NULL"
    subject = row[1] if row[1] else "NULL"
    count = row[2] if row[2] else 0
    print(f"{year:<8} {subject:<10} {count:<6}")

# 总计
cursor.execute("SELECT COUNT(*) FROM exam_questions")
total = cursor.fetchone()[0]
print(f"\n总计: {total} 道题")

# 示例题目
print("\n" + "=" * 60)
print("示例题目（前3道）")
print("=" * 60)
cursor.execute("SELECT id, subject, year, stem FROM exam_questions LIMIT 3")
for i, row in enumerate(cursor.fetchall(), 1):
    print(f"\n[{i}] ID: {row[0]}")
    print(f"    科目: {row[1]} | 年份: {row[2]}")
    print(f"    题干: {row[3][:100]}...")

conn.close()
print("\n" + "=" * 60)
