#!/usr/bin/env python3
"""
code-199 单词本迁移脚本
将 Markdown 格式单词转换为 SQLite 数据库
"""
import os
import sys
import io
import sqlite3
import yaml
import json
from pathlib import Path

# 修复 Windows 编码问题
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 路径配置
CODE199_VOCAB_DIR = Path("D:/newIDeaProject/code-199/content/vocabulary/english")
OUTPUT_DB = Path("app/src/main/assets/vocabulary.db")

def parse_markdown_word(file_path):
    """解析单个单词 Markdown 文件"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 分离 frontmatter 和正文
    if not content.startswith('---'):
        return None

    parts = content.split('---', 2)
    if len(parts) < 3:
        return None

    frontmatter = yaml.safe_load(parts[1])
    explanation = parts[2].strip()

    return {
        'id': frontmatter.get('id', f"vocab-{frontmatter['word']}"),
        'word': frontmatter['word'],
        'phonetic': frontmatter.get('phonetic'),
        'definitions': json.dumps(frontmatter.get('definitions', []), ensure_ascii=False),
        'synonyms': json.dumps(frontmatter.get('synonyms', []), ensure_ascii=False) if frontmatter.get('synonyms') else None,
        'confusables': json.dumps(frontmatter.get('confusables', []), ensure_ascii=False) if frontmatter.get('confusables') else None,
        'tags': json.dumps(frontmatter.get('tags', []), ensure_ascii=False) if frontmatter.get('tags') else None,
        'explanation': explanation,
        'status': frontmatter.get('status', 'new')
    }

def migrate_vocabulary():
    """迁移所有单词到数据库"""

    # 创建输出目录
    OUTPUT_DB.parent.mkdir(parents=True, exist_ok=True)

    # 删除旧数据库
    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()

    # 创建数据库
    conn = sqlite3.connect(OUTPUT_DB)
    cursor = conn.cursor()

    # 创建表
    cursor.execute("""
        CREATE TABLE vocabulary (
            id TEXT PRIMARY KEY,
            word TEXT NOT NULL,
            phonetic TEXT,
            definitions TEXT NOT NULL,
            synonyms TEXT,
            confusables TEXT,
            tags TEXT,
            explanation TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'new',
            review_count INTEGER NOT NULL DEFAULT 0,
            last_review_at INTEGER,
            next_review_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE vocabulary_reviews (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vocab_id TEXT NOT NULL,
            is_correct INTEGER NOT NULL,
            review_type TEXT NOT NULL,
            time_spent INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(vocab_id) REFERENCES vocabulary(id) ON DELETE CASCADE
        )
    """)

    # 创建索引
    cursor.execute("CREATE INDEX idx_vocab_word ON vocabulary(word)")
    cursor.execute("CREATE INDEX idx_vocab_status ON vocabulary(status)")
    cursor.execute("CREATE INDEX idx_vocab_next_review ON vocabulary(next_review_at)")

    # 迁移单词
    count = 0
    skipped = 0

    for md_file in CODE199_VOCAB_DIR.glob("*.md"):
        try:
            word_data = parse_markdown_word(md_file)
            if not word_data:
                skipped += 1
                continue

            cursor.execute("""
                INSERT INTO vocabulary
                (id, word, phonetic, definitions, synonyms, confusables, tags,
                 explanation, status, review_count, last_review_at, next_review_at,
                 created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?, ?)
            """, (
                word_data['id'],
                word_data['word'],
                word_data['phonetic'],
                word_data['definitions'],
                word_data['synonyms'],
                word_data['confusables'],
                word_data['tags'],
                word_data['explanation'],
                word_data['status'],
                int(md_file.stat().st_mtime * 1000),
                int(md_file.stat().st_mtime * 1000)
            ))

            count += 1
            print(f"[OK] {word_data['word']}")

        except Exception as e:
            print(f"[SKIP] {md_file.name}: {e}")
            skipped += 1

    conn.commit()
    conn.close()

    print(f"\n=== 迁移完成 ===")
    print(f"成功: {count} 个单词")
    print(f"跳过: {skipped} 个")
    print(f"输出: {OUTPUT_DB}")

if __name__ == "__main__":
    migrate_vocabulary()
