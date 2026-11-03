#!/usr/bin/env python3
"""Print SQL that loads every table read the app's source makes into sec.app_reads.

The reads come from lib/, so a column added to a Dart select list is tested on the
next CI run with no copy to keep in step. A read this cannot parse stops the run,
because a skipped read would look the same as a covered one.
"""
import pathlib
import re
import sys

CHAIN = re.compile(r"\.from\(\s*([^()]+?)\s*,?\s*\)\s*\.select\(")
LITERAL = re.compile(r"'([^'$\\]*)'")
COLUMN_ARG = re.compile(r"\.\w+\(\s*'(\w+)'")
EMBED = re.compile(r"^(\w+)!(\w+)\((.*)\)$")
# The one read whose table arrives as a parameter.
PARAMETERS = {("product_submission_service.dart", "table"): "product_submissions"}


def fail(message):
    sys.exit(f"app_reads.py: {message}")


def closing_paren(text, start):
    depth, quoted = 1, False
    for index in range(start, len(text)):
        char = text[index]
        if char == "'":
            quoted = not quoted
        elif not quoted and char == "(":
            depth += 1
        elif not quoted and char == ")":
            depth -= 1
            if depth == 0:
                return index
    fail("unbalanced select call")


def top_level(items):
    parts, depth, current = [], 0, ""
    for char in items:
        depth += (char == "(") - (char == ")")
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    return parts + [current.strip()] if current.strip() else parts


def resolve_table(raw, path, constants):
    if raw.startswith("'"):
        return raw.strip("'")
    if raw.startswith("SupabaseContract."):
        name = raw.split(".", 1)[1]
        if name in constants:
            return constants[name]
    if (path.name, raw) in PARAMETERS:
        return PARAMETERS[(path.name, raw)]
    fail(f"{path}: cannot resolve table {raw!r}")


def reads(lib):
    contract = (lib / "data/supabase/supabase_contract.dart").read_text()
    constants = dict(re.findall(r"static const (\w+)\s*=\s*'([^']+)'", contract))
    for path in sorted(lib.rglob("*.dart")):
        text = path.read_text()
        for match in CHAIN.finditer(text):
            end = closing_paren(text, match.end())
            argument = text[match.end():end]
            if LITERAL.sub("", argument).strip(" \n,"):
                fail(f"{path}: select list is not a plain string: {argument.strip()!r}")
            select = "".join(LITERAL.findall(argument))
            if not select or "*" in select:
                fail(f"{path}: select must name its columns, or column grants break it")
            table = resolve_table(match.group(1), path, constants)
            chain_end = text.find(";", end)
            filters = COLUMN_ARG.findall(text[end:chain_end])
            columns = []
            for item in top_level(select):
                embed = EMBED.match(item)
                if embed:
                    yield table, embed[1], embed[2], top_level(embed[3])
                else:
                    columns.append(item)
            yield table, table, None, columns + filters


def literal(value):
    return "NULL" if value is None else "'" + value.replace("'", "''") + "'"


def main():
    rows = sorted(set(
        (parent, table, fk, ",".join(dict.fromkeys(columns)))
        for parent, table, fk, columns in reads(pathlib.Path(sys.argv[1]))
    ), key=str)
    if not rows:
        fail("found no reads")
    print("INSERT INTO sec.app_reads(parent_table, table_name, embedded_fk, columns) VALUES")
    print(",\n".join("(" + ", ".join(map(literal, row)) + ")" for row in rows) + ";")


main()
