#!/usr/bin/env python3
"""
code-199 真题数据迁移工具
从 Markdown 格式迁移到 Android Room 数据库
"""
import os
import re
import json
import sqlite3
from pathlib import Path
from datetime import datetime
import yaml

# 路径配置
CODE_199_PATH = Path(r"D:\newIDeaProject\code-199\content")
TARGET_DB_PATH = Path(r"D:\newIDeaProject\mem-coach-app\app\src\main\assets\exam_questions.db")

# 科目映射
SUBJECT_MAP = {
    "math": "数学",
    "logic": "逻辑",
    "english": "英语",
    "writing": "写作"
}

# 题型映射
TYPE_MAP = {
    "choice": "选择题",
    "multi_choice": "多选题",
    "essay": "论述题",
    "analysis": "论证有效性分析",
    "argument_writing": "论说文"
}

def parse_markdown_question(file_path):
    """解析 Markdown 题目文件"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 分离 YAML frontmatter 和正文
    if content.startswith('---'):
        parts = content.split('---', 2)
        if len(parts) >= 3:
            frontmatter = yaml.safe_load(parts[1])
            body = parts[2].strip()
        else:
            return None
    else:
        return None

    # 解析正文各部分
    question = {
        'id': frontmatter.get('id', ''),
        'year': extract_year(frontmatter.get('id', '')),
        'subject': frontmatter.get('subject', ''),
        'section': extract_section(frontmatter),
        'question_number': extract_question_number(frontmatter.get('id', '')),
        'type': frontmatter.get('type', 'choice'),
        'difficulty': frontmatter.get('difficulty', 3),
        'knowledge_points': frontmatter.get('knowledge_points', []),
        'tags': frontmatter.get('tags', []),
        'source': frontmatter.get('source', ''),
    }

    # 提取题干
    stem_match = re.search(r'##\s*题目\s*\n(.*?)(?=\n##|$)', body, re.DOTALL)
    question['stem'] = stem_match.group(1).strip() if stem_match else ''

    # 提取选项
    options_match = re.search(r'##\s*选项\s*\n(.*?)(?=\n##|$)', body, re.DOTALL)
    if options_match:
        options_text = options_match.group(1).strip()
        question['options'] = parse_options(options_text)
    else:
        question['options'] = None

    # 提取答案
    answer_match = re.search(r'##\s*答案\s*\n(.*?)(?=\n##|$)', body, re.DOTALL)
    question['answer'] = answer_match.group(1).strip() if answer_match else ''

    # 提取解析
    explanation_match = re.search(r'##\s*解析\s*\n(.*)', body, re.DOTALL)
    question['explanation'] = explanation_match.group(1).strip() if explanation_match else ''

    return question

def extract_year(question_id):
    """从 ID 提取年份"""
    match = re.match(r'(\d{4})-', question_id)
    return int(match.group(1)) if match else None

def extract_question_number(question_id):
    """从 ID 提取题号"""
    match = re.search(r'-q(\d+)', question_id)
    return int(match.group(1)) if match else None

def extract_section(frontmatter):
    """从知识点提取小模块"""
    kps = frontmatter.get('knowledge_points', [])
    if kps:
        return kps[0]
    return None

def parse_options(options_text):
    """解析选项文本为 JSON"""
    options = {}
    lines = options_text.strip().split('\n')
    for line in lines:
        match = re.match(r'^([A-E])\.\s*(.+)$', line.strip())
        if match:
            options[match.group(1)] = match.group(2).strip()
    return json.dumps(options, ensure_ascii=False) if options else None

def create_database(db_path):
    """创建数据库表"""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute('''
    CREATE TABLE IF NOT EXISTS exam_questions (
        id TEXT PRIMARY KEY,
        year INTEGER,
        subject TEXT NOT NULL,
        section TEXT,
        question_number INTEGER,
        type TEXT NOT NULL,
        difficulty INTEGER DEFAULT 3,
        stem TEXT NOT NULL,
        options TEXT,
        answer TEXT NOT NULL,
        explanation TEXT,
        knowledge_points TEXT,
        tags TEXT,
        source TEXT,
        source_text TEXT,
        stem_hash TEXT,
        parse_confidence REAL DEFAULT 1.0,
        parse_status TEXT DEFAULT 'imported',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
    )
    ''')

    conn.commit()
    return conn

def migrate_questions(source_dir, db_conn):
    """迁移所有题目"""
    questions_dir = source_dir / "questions"
    cursor = db_conn.cursor()

    success_count = 0
    error_count = 0

    for md_file in questions_dir.glob("*.md"):
        try:
            question = parse_markdown_question(md_file)
            if not question:
                print(f"[FAIL] 解析失败: {md_file.name}")
                error_count += 1
                continue

            now = int(datetime.now().timestamp() * 1000)

            cursor.execute('''
            INSERT OR REPLACE INTO exam_questions
            (id, year, subject, section, question_number, type, difficulty,
             stem, options, answer, explanation, knowledge_points, tags, source,
             parse_status, parse_confidence, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                question['id'],
                question['year'],
                question['subject'],
                question['section'],
                question['question_number'],
                question['type'],
                question['difficulty'],
                question['stem'],
                question['options'],
                question['answer'],
                question['explanation'],
                json.dumps(question['knowledge_points'], ensure_ascii=False),
                json.dumps(question['tags'], ensure_ascii=False),
                question['source'],
                'imported',
                1.0,
                now,
                now
            ))

            success_count += 1
            if success_count % 50 == 0:
                print(f"[PROGRESS] 已迁移 {success_count} 道题...")

        except Exception as e:
            print(f"[ERROR] 错误 [{md_file.name}]: {e}")
            error_count += 1

    db_conn.commit()
    return success_count, error_count

def main():
    import sys
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

    print("=" * 60)
    print("code-199 真题数据迁移工具")
    print("=" * 60)

    # 创建数据库
    print(f"\n[DB] 创建数据库: {TARGET_DB_PATH}")
    conn = create_database(TARGET_DB_PATH)

    # 迁移题目
    print(f"\n[START] 开始迁移题目...")
    success, error = migrate_questions(CODE_199_PATH, conn)

    # 统计
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM exam_questions")
    total = cursor.fetchone()[0]

    cursor.execute("SELECT subject, COUNT(*) FROM exam_questions GROUP BY subject")
    by_subject = cursor.fetchall()

    print("\n" + "=" * 60)
    print("[STAT] 迁移完成统计")
    print("=" * 60)
    print(f"[OK] 成功: {success} 道")
    print(f"[ERR] 失败: {error} 道")
    print(f"[TOTAL] 数据库总计: {total} 道")
    print("\n按科目统计:")
    for subject, count in by_subject:
        print(f"  - {SUBJECT_MAP.get(subject, subject)}: {count} 道")

    conn.close()
    print(f"\n[SAVE] 数据库已保存到: {TARGET_DB_PATH}")
    print("=" * 60)

if __name__ == "__main__":
    main()
