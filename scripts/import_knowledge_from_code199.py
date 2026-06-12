"""
从 code-199 项目导入知识点到 knowledge.db
"""
import sqlite3
from pathlib import Path
import re

# 路径配置
CODE199_KNOWLEDGE = Path(r"D:\newIDeaProject\code-199\content\knowledge")
OUTPUT_DB = Path(r"d:\newIDeaProject\mem-coach-app\app\src\main\assets\knowledge.db")

def parse_frontmatter(content):
    """解析markdown的frontmatter"""
    if not content.startswith('---'):
        return {}, content

    parts = content.split('---', 2)
    if len(parts) < 3:
        return {}, content

    meta = {}
    for line in parts[1].strip().split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            meta[key.strip()] = value.strip()

    return meta, parts[2].strip()

def extract_description(content):
    """从markdown提取描述（第一段或核心概念）"""
    lines = content.strip().split('\n')
    for i, line in enumerate(lines):
        if line.strip() and not line.startswith('#'):
            # 找到第一个非标题段落
            desc = line.strip()
            if len(desc) > 200:
                desc = desc[:200] + '...'
            return desc
    return None

def create_knowledge_db():
    """创建knowledge.db并建表"""
    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()
        print(f"✓ 删除旧数据库")

    conn = sqlite3.connect(OUTPUT_DB)
    cursor = conn.cursor()

    # 创建knowledge_nodes表（参考AppDatabase的结构）
    cursor.execute("""
        CREATE TABLE knowledge_nodes (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            subject TEXT NOT NULL,
            chapter TEXT,
            parent_id TEXT,
            description TEXT,
            content TEXT,
            exam_frequency INTEGER NOT NULL DEFAULT 0,
            sort_weight INTEGER NOT NULL DEFAULT 0
        )
    """)

    print(f"✓ 创建knowledge_nodes表")
    conn.commit()
    return conn

def import_knowledge(conn):
    """导入知识点"""
    cursor = conn.cursor()
    total = 0
    skipped = 0

    for category in ["logic", "math", "writing"]:
        category_dir = CODE199_KNOWLEDGE / category
        if not category_dir.exists():
            print(f"⚠ 目录不存在: {category_dir}")
            continue

        print(f"\n处理 {category} 知识点...")

        for md_file in category_dir.glob("*.md"):
            try:
                content = md_file.read_text(encoding='utf-8')
                meta, body = parse_frontmatter(content)

                # 提取字段
                kp_id = meta.get('id', md_file.stem)
                title = meta.get('title', md_file.stem.replace('-', ' ').title())
                chapter = meta.get('chapter', '')
                importance = meta.get('importance', 'medium')

                # 映射科目
                subject_map = {
                    'logic': 'logic',
                    'math': 'math',
                    'writing': 'writing'
                }
                subject = subject_map.get(category, category)

                # 拼接科目前缀以防止不同学科同名知识点的 ID 冲突
                kp_id = f"{subject}_{kp_id}"

                # 考频映射
                freq_map = {'high': 3, 'medium': 2, 'low': 1}
                exam_freq = freq_map.get(importance, 0)

                # 提取描述
                description = extract_description(body)

                # 插入数据
                cursor.execute("""
                    INSERT INTO knowledge_nodes
                    (id, name, subject, chapter, description, content, exam_frequency, sort_weight)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (kp_id, title, subject, chapter, description, body, exam_freq, 0))

                total += 1
                if total % 100 == 0:
                    print(f"  已导入 {total} 条...")

            except Exception as e:
                print(f"✗ 错误: {md_file.name} - {e}")
                skipped += 1

    conn.commit()
    print(f"\n✓ 导入完成: {total} 条成功, {skipped} 条跳过")
    return total

def main():
    print("=== 从 code-199 导入知识点 ===\n")

    # 检查源目录
    if not CODE199_KNOWLEDGE.exists():
        print(f"✗ 源目录不存在: {CODE199_KNOWLEDGE}")
        return

    # 创建数据库
    conn = create_knowledge_db()

    # 导入知识点
    total = import_knowledge(conn)

    # 统计
    cursor = conn.cursor()
    for subject in ['logic', 'math', 'writing']:
        count = cursor.execute(
            "SELECT COUNT(*) FROM knowledge_nodes WHERE subject = ?",
            (subject,)
        ).fetchone()[0]
        print(f"  {subject}: {count} 条")

    conn.close()
    print(f"\n✓ 数据库已生成: {OUTPUT_DB}")
    print(f"✓ 大小: {OUTPUT_DB.stat().st_size / 1024 / 1024:.2f} MB")

if __name__ == '__main__':
    main()
