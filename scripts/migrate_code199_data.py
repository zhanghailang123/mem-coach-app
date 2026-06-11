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

# 管综小模块映射
SECTION_MAP = {
    "math": "数学",
    "logic": "逻辑",
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

CONDITION_SUFFICIENCY_OPTIONS = {
    "A": "条件(1)充分，但条件(2)不充分。",
    "B": "条件(2)充分，但条件(1)不充分。",
    "C": "条件(1)和条件(2)单独都不充分，但联合起来充分。",
    "D": "条件(1)充分，条件(2)也充分。",
    "E": "条件(1)和条件(2)单独都不充分，联合起来也不充分。",
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
    source_subject = frontmatter.get('subject', '')
    knowledge_points = frontmatter.get('knowledge_points', [])
    tags = frontmatter.get('tags', [])
    question = {
        'id': frontmatter.get('id', ''),
        'year': extract_year(frontmatter.get('id', '')),
        'subject': normalize_subject(source_subject),
        'section': normalize_section(source_subject),
        'topic': extract_topic(knowledge_points),
        'question_number': extract_question_number(frontmatter.get('id', '')),
        'type': frontmatter.get('type', 'choice'),
        'difficulty': normalize_difficulty(frontmatter.get('difficulty', 3)),
        'knowledge_points': knowledge_points,
        'knowledge_tags': merge_tags(knowledge_points, tags),
        'tags': tags,
        'source': frontmatter.get('source', ''),
    }

    # 提取题干
    stem_match = re.search(r'##\s*题目\s*\n(.*?)(?=\n##|$)', body, re.DOTALL)
    question['stem'] = stem_match.group(1).strip() if stem_match else ''

    # 提取选项
    options_match = re.search(r'##\s*选项\s*\n(.*?)(?=\n##|$)', body, re.DOTALL)
    if options_match:
        options_text = options_match.group(1).strip()
        question_type = str(question.get('type') or '')
        if is_condition_sufficiency(question_type, tags, options_text):
            conditions = parse_condition_sufficiency_conditions(options_text)
            question['stem'] = append_conditions_to_stem(question['stem'], conditions)
            question['options'] = json.dumps(CONDITION_SUFFICIENCY_OPTIONS, ensure_ascii=False)
        else:
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

def extract_topic(knowledge_points):
    """从知识点提取主知识点"""
    return knowledge_points[0] if knowledge_points else None

def normalize_subject(raw_subject):
    """code-199 的 math/logic/writing 属于管综大科目"""
    if raw_subject in ("math", "logic", "writing"):
        return "management_comprehensive"
    if raw_subject in ("english", "english2", "english_ii"):
        return "english"
    return raw_subject or "management_comprehensive"

def normalize_section(raw_subject):
    """code-199 的 subject 在 MEM Coach 中是小模块 section"""
    if raw_subject in ("math", "logic", "writing"):
        return raw_subject
    if raw_subject in ("english", "english2", "english_ii"):
        return "english"
    return None

def normalize_difficulty(raw):
    """Room 中 difficulty 使用 basic/medium/hard 文本。"""
    value = str(raw).strip()
    if value == "1":
        return "basic"
    if value in ("2", "3"):
        return "medium"
    if value in ("4", "5"):
        return "hard"
    return value or None

def merge_tags(*groups):
    """合并 code-199 的 knowledge_points 和 tags，保持原顺序去重。"""
    merged = []
    seen = set()
    for group in groups:
        for item in group or []:
            text = str(item).strip()
            if text and text not in seen:
                merged.append(text)
                seen.add(text)
    return merged

def parse_options(options_text):
    """解析选项文本为 JSON"""
    options = {}
    lines = options_text.strip().split('\n')
    for line in lines:
        match = re.match(r'^([A-E])[\.\、\s]+(.+)$', line.strip())
        if match:
            options[match.group(1)] = match.group(2).strip()
    return json.dumps(options, ensure_ascii=False) if options else None

def is_condition_sufficiency(question_type, tags, options_text):
    """判断是否为管综数学条件充分性题。"""
    if question_type == "condition_sufficiency":
        return True
    if "条件充分性判断" in (tags or []):
        return True
    return bool(re.search(r'条件\s*[\(（]\s*1\s*[\)）]', options_text or '')) and bool(
        re.search(r'条件\s*[\(（]\s*2\s*[\)）]', options_text or '')
    )

def parse_condition_sufficiency_conditions(options_text):
    """从 code-199 的条件充分性选项区提取条件(1)/(2)文本。"""
    text = (options_text or '').strip()
    matches = list(re.finditer(r'条件\s*[\(（]\s*([12])\s*[\)）]\s*[:：]?', text))
    if len(matches) < 2:
        return []

    conditions = []
    for index, match in enumerate(matches[:2]):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        content = text[start:end].strip()
        content = re.sub(r'^\s*\|\s*', '', content)
        content = re.sub(r'\s*\|\s*$', '', content)
        if content:
            conditions.append(content.strip())
    return conditions

def append_conditions_to_stem(stem, conditions):
    """将条件充分性题的条件文本并入题干，避免移动端丢失条件。"""
    stem = stem or ''
    if not conditions:
        return stem
    if "条件(1)" in stem or "条件（1）" in stem:
        return stem
    condition_lines = [f"{index}. {content}" for index, content in enumerate(conditions, start=1)]
    return f"{stem.strip()}\n\n**已知条件：**\n" + "\n".join(condition_lines)

def create_database(db_path):
    """创建数据库表"""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute('''
    DROP TABLE IF EXISTS exam_questions
    ''')

    cursor.execute('''
    CREATE TABLE exam_questions (
        id TEXT PRIMARY KEY NOT NULL,
        year INTEGER NOT NULL,
        subject TEXT NOT NULL,
        section TEXT,
        question_number INTEGER,
        chapter TEXT,
        topic TEXT,
        type TEXT NOT NULL,
        difficulty TEXT,
        stem TEXT NOT NULL,
        options TEXT,
        answer TEXT,
        explanation TEXT,
        source_file TEXT NOT NULL,
        source_document_id TEXT,
        source_page INTEGER NOT NULL DEFAULT 0,
        knowledge_tags TEXT,
        source_text TEXT,
        source_page_type TEXT,
        answer_source_text TEXT,
        answer_source_page INTEGER,
        merge_status TEXT NOT NULL DEFAULT 'merged',
        stem_hash TEXT,
        parse_confidence REAL NOT NULL DEFAULT 1.0,
        parse_status TEXT NOT NULL DEFAULT 'parsed',
        parse_notes TEXT,
        exam_frequency INTEGER NOT NULL DEFAULT 0,
        embedding BLOB,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
    )
    ''')

    cursor.execute("CREATE INDEX IF NOT EXISTS index_exam_questions_stem_hash ON exam_questions(stem_hash)")
    cursor.execute("CREATE INDEX IF NOT EXISTS index_exam_questions_parse_status ON exam_questions(parse_status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS index_exam_questions_section ON exam_questions(section)")
    cursor.execute("CREATE INDEX IF NOT EXISTS index_exam_questions_question_number ON exam_questions(question_number)")
    cursor.execute("CREATE INDEX IF NOT EXISTS index_exam_questions_merge_status ON exam_questions(merge_status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS index_exam_questions_source_document_id ON exam_questions(source_document_id)")

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
            if not question['year'] or not question['question_number'] or not question['section']:
                print(f"[SKIP] 跳过非标准题目: {md_file.name}")
                error_count += 1
                continue

            now = int(datetime.now().timestamp() * 1000)

            cursor.execute('''
            INSERT OR REPLACE INTO exam_questions
            (id, year, subject, section, question_number, chapter, topic, type, difficulty,
             stem, options, answer, explanation, source_file, source_document_id, source_page,
             knowledge_tags, source_text, source_page_type, answer_source_text, answer_source_page,
             merge_status, stem_hash, parse_confidence, parse_status, parse_notes, exam_frequency,
             embedding, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                question['id'],
                question['year'],
                question['subject'],
                question['section'],
                question['question_number'],
                None,
                question['topic'],
                question['type'],
                question['difficulty'],
                question['stem'],
                question['options'],
                question['answer'],
                question['explanation'],
                question['source'],
                None,
                0,
                json.dumps(question['knowledge_tags'], ensure_ascii=False),
                None,
                'imported',
                None,
                None,
                'merged',
                None,
                1.0,
                'parsed',
                None,
                0,
                None,
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

    cursor.execute("SELECT subject, section, COUNT(*) FROM exam_questions GROUP BY subject, section ORDER BY subject, section")
    by_section = cursor.fetchall()

    print("\n" + "=" * 60)
    print("[STAT] 迁移完成统计")
    print("=" * 60)
    print(f"[OK] 成功: {success} 道")
    print(f"[ERR] 失败: {error} 道")
    print(f"[TOTAL] 数据库总计: {total} 道")
    print("\n按科目/模块统计:")
    for subject, section, count in by_section:
        section_name = SECTION_MAP.get(section, section)
        print(f"  - {subject}/{section_name}: {count} 道")

    conn.close()
    print(f"\n[SAVE] 数据库已保存到: {TARGET_DB_PATH}")
    print("=" * 60)

if __name__ == "__main__":
    main()
