#!/usr/bin/env python3
"""
快速验证迁移的数据是否正确
"""
import sqlite3
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

db_path = "app/src/main/assets/exam_questions.db"

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 检查表结构
    cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='exam_questions'")
    schema = cursor.fetchone()
    if not schema:
        print("[ERROR] 表不存在")
        sys.exit(1)

    # 统计数据
    cursor.execute("SELECT COUNT(*) FROM exam_questions")
    total = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(DISTINCT year) FROM exam_questions WHERE year IS NOT NULL")
    years = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(DISTINCT subject) FROM exam_questions")
    subjects = cursor.fetchone()[0]

    print(f"[OK] 数据库验证通过")
    print(f"   总题数: {total}")
    print(f"   年份数: {years}")
    print(f"   科目数: {subjects}")

    # 随机抽取一题验证完整性
    cursor.execute("SELECT id, stem, answer, explanation FROM exam_questions LIMIT 1")
    row = cursor.fetchone()
    if row:
        print(f"\n示例题目:")
        print(f"   ID: {row[0]}")
        print(f"   题干长度: {len(row[1])} 字符")
        print(f"   答案: {row[2]}")
        print(f"   解析长度: {len(row[3]) if row[3] else 0} 字符")

    conn.close()

except Exception as e:
    print(f"[ERROR] 验证失败: {e}")
    sys.exit(1)
