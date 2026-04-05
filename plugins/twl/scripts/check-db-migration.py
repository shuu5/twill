#!/usr/bin/env python3
"""
Zodスキーマ ↔ DBマイグレーション整合性チェック

packages/schema/src/**/*.ts のZodフィールドと
supabase/migrations/*.sql のCREATE TABLE/ALTER TABLE文を突合し、
スキーマにあるがDBにないカラムを検出する。

Usage:
    python3 check-db-migration.py <project-root>
    python3 check-db-migration.py <project-root> --json
"""

import json
import os
import re
import sys
from glob import glob
from pathlib import Path


def parse_migrations(migrations_dir: str) -> dict[str, set[str]]:
    """supabase/migrations/*.sql を時系列順に解析し、テーブル→カラム集合を構築"""
    tables: dict[str, set[str]] = {}

    sql_files = sorted(glob(os.path.join(migrations_dir, "*.sql")))
    for sql_file in sql_files:
        with open(sql_file, "r", encoding="utf-8") as f:
            content = f.read()

        # 単一行コメントと複数行コメントを除去
        content = re.sub(r"--[^\n]*", "", content)
        content = re.sub(r"/\*.*?\*/", "", content, flags=re.DOTALL)

        # CREATE TABLE
        for match in re.finditer(
            r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?\"?(\w+)\"?\s*\((.*?)\);",
            content,
            re.IGNORECASE | re.DOTALL,
        ):
            table_name = match.group(1)
            columns_block = match.group(2)
            columns = _parse_column_definitions(columns_block)
            tables[table_name] = columns

        # ALTER TABLE ADD COLUMN
        for match in re.finditer(
            r"ALTER\s+TABLE\s+(?:(?:ONLY\s+)?(?:public\.)?)?\"?(\w+)\"?\s+ADD\s+(?:COLUMN\s+)?(?:IF\s+NOT\s+EXISTS\s+)?\"?(\w+)\"?",
            content,
            re.IGNORECASE,
        ):
            table_name = match.group(1)
            col_name = match.group(2)
            if table_name not in tables:
                tables[table_name] = set()
            tables[table_name].add(col_name)

        # ALTER TABLE RENAME COLUMN
        for match in re.finditer(
            r"ALTER\s+TABLE\s+(?:(?:ONLY\s+)?(?:public\.)?)?\"?(\w+)\"?\s+RENAME\s+COLUMN\s+\"?(\w+)\"?\s+TO\s+\"?(\w+)\"?",
            content,
            re.IGNORECASE,
        ):
            table_name = match.group(1)
            old_col = match.group(2)
            new_col = match.group(3)
            if table_name in tables:
                tables[table_name].discard(old_col)
                tables[table_name].add(new_col)

        # ALTER TABLE DROP COLUMN
        for match in re.finditer(
            r"ALTER\s+TABLE\s+(?:(?:ONLY\s+)?(?:public\.)?)?\"?(\w+)\"?\s+DROP\s+COLUMN\s+(?:IF\s+EXISTS\s+)?\"?(\w+)\"?",
            content,
            re.IGNORECASE,
        ):
            table_name = match.group(1)
            col_name = match.group(2)
            if table_name in tables:
                tables[table_name].discard(col_name)

    return tables


def _parse_column_definitions(columns_block: str) -> set[str]:
    """CREATE TABLE内のカラム定義からカラム名を抽出"""
    columns = set()
    # 制約定義を除外するキーワード
    constraint_keywords = {
        "PRIMARY",
        "UNIQUE",
        "CHECK",
        "FOREIGN",
        "CONSTRAINT",
        "EXCLUDE",
    }

    for line in columns_block.split(","):
        line = line.strip()
        if not line:
            continue
        first_word = line.split()[0].strip('"').upper() if line.split() else ""
        if first_word in constraint_keywords:
            continue
        # カラム名は最初の単語
        col_match = re.match(r'"?(\w+)"?\s+\w+', line)
        if col_match:
            columns.add(col_match.group(1))

    return columns


def parse_zod_schemas(
    schema_dir: str,
) -> dict[str, dict[str, list[dict[str, str | bool]]]]:
    """
    packages/schema/src/**/*.ts からZodオブジェクト定義を解析

    Returns:
        {table_name: {"fields": [{"name": str, "optional": bool}], "file": str}}
    """
    schemas: dict[str, dict] = {}
    ts_files = glob(os.path.join(schema_dir, "**", "*.ts"), recursive=True)

    for ts_file in ts_files:
        with open(ts_file, "r", encoding="utf-8") as f:
            content = f.read()

        # z.object({...}) ブロックを検出（export const XxxSchema = z.object({...})）
        for match in re.finditer(
            r"(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*z\.object\(\{(.*?)\}\)",
            content,
            re.DOTALL,
        ):
            schema_name = match.group(1)
            fields_block = match.group(2)
            table_name = _schema_name_to_table(schema_name)

            fields = _parse_zod_fields(fields_block)
            if fields:
                schemas[table_name] = {
                    "fields": fields,
                    "file": os.path.relpath(ts_file, os.path.dirname(schema_dir)),
                    "schema_name": schema_name,
                }

    return schemas


def _schema_name_to_table(schema_name: str) -> str:
    """
    Zodスキーマ名からテーブル名を推定
    例: interviewStateSchema -> interview_state
        MessagesInsertSchema -> messages
        userProfileSchema -> user_profile
    """
    # Schema/Insert/Update/Row 等のサフィックスを除去
    name = re.sub(r"(Schema|Insert|Update|Row|Select)$", "", schema_name)
    # camelCase/PascalCase → snake_case
    name = re.sub(r"([A-Z])", r"_\1", name).lower().strip("_")
    # 重複アンダースコアを除去
    name = re.sub(r"_+", "_", name)
    return name


def _parse_zod_fields(fields_block: str) -> list[dict[str, str | bool]]:
    """Zodオブジェクトのフィールド定義を解析"""
    fields = []

    # フィールド名: z.xxx() パターン
    for match in re.finditer(
        r"(\w+)\s*:\s*(z\.[^,}]+(?:\([^)]*\)[^,}]*)*)", fields_block
    ):
        field_name = match.group(1)
        field_def = match.group(2)

        is_optional = bool(
            re.search(r"\.(optional|nullable|nullish)\(\)", field_def)
        )

        fields.append(
            {
                "name": _camel_to_snake(field_name),
                "zod_name": field_name,
                "optional": is_optional,
            }
        )

    return fields


def _camel_to_snake(name: str) -> str:
    """camelCase → snake_case"""
    result = re.sub(r"([A-Z])", r"_\1", name).lower().strip("_")
    return re.sub(r"_+", "_", result)


def check_integrity(
    db_tables: dict[str, set[str]],
    zod_schemas: dict[str, dict],
) -> dict:
    """Zodスキーマ↔DB整合性チェック"""
    errors = []
    warnings = []
    checked_tables = []

    for table_name, schema_info in zod_schemas.items():
        if table_name not in db_tables:
            # テーブル名マッピング不能 or テーブル自体がない
            # 複数形を試す
            plural = table_name + "s"
            if plural in db_tables:
                db_columns = db_tables[plural]
                actual_table = plural
            else:
                warnings.append(
                    {
                        "type": "table_not_found",
                        "table": table_name,
                        "schema_name": schema_info["schema_name"],
                        "file": schema_info["file"],
                        "message": f"テーブル '{table_name}' がマイグレーションに見つかりません（マッピング不能の可能性）",
                    }
                )
                continue
        else:
            db_columns = db_tables[table_name]
            actual_table = table_name

        checked_tables.append(actual_table)

        for field in schema_info["fields"]:
            col_name = field["name"]
            if col_name not in db_columns:
                entry = {
                    "table": actual_table,
                    "column": col_name,
                    "zod_field": field["zod_name"],
                    "schema_name": schema_info["schema_name"],
                    "file": schema_info["file"],
                    "optional": field["optional"],
                    "message": f"カラム '{actual_table}.{col_name}' がマイグレーションに存在しません（Zodフィールド: {field['zod_name']}）",
                }
                if field["optional"]:
                    entry["level"] = "WARNING"
                    warnings.append(entry)
                else:
                    entry["level"] = "ERROR"
                    errors.append(entry)

    # 全体ステータス判定
    if errors:
        status = "FAIL"
    elif warnings:
        status = "WARN"
    else:
        status = "PASS"

    return {
        "status": status,
        "errors": errors,
        "warnings": warnings,
        "checked_tables": checked_tables,
    }


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <project-root> [--json]", file=sys.stderr)
        sys.exit(1)

    project_root = sys.argv[1]
    json_output = "--json" in sys.argv

    schema_dir = os.path.join(project_root, "packages", "schema", "src")
    migrations_dir = os.path.join(project_root, "supabase", "migrations")

    # 前提条件チェック
    if not os.path.isdir(schema_dir):
        result = {"status": "SKIP", "reason": f"packages/schema/src/ が存在しません: {schema_dir}"}
        if json_output:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(f"SKIP: {result['reason']}")
        sys.exit(0)

    if not os.path.isdir(migrations_dir):
        result = {"status": "SKIP", "reason": f"supabase/migrations/ が存在しません: {migrations_dir}"}
        if json_output:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(f"SKIP: {result['reason']}")
        sys.exit(0)

    # 解析と検証
    db_tables = parse_migrations(migrations_dir)
    zod_schemas = parse_zod_schemas(schema_dir)

    if not zod_schemas:
        result = {"status": "SKIP", "reason": "Zodスキーマが検出されませんでした"}
        if json_output:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(f"SKIP: {result['reason']}")
        sys.exit(0)

    result = check_integrity(db_tables, zod_schemas)

    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"Status: {result['status']}")
        print(f"Checked tables: {', '.join(result['checked_tables']) or 'none'}")
        if result["errors"]:
            print(f"\nERRORS ({len(result['errors'])}):")
            for e in result["errors"]:
                print(f"  ✗ {e['message']}")
        if result["warnings"]:
            print(f"\nWARNINGS ({len(result['warnings'])}):")
            for w in result["warnings"]:
                print(f"  ⚠ {w['message']}")

    # exit code: FAIL=1, WARN=0, PASS=0, SKIP=0
    sys.exit(1 if result["status"] == "FAIL" else 0)


if __name__ == "__main__":
    main()
