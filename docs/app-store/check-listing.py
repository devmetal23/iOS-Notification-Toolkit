#!/usr/bin/env python3
"""Check App Store copy in docs/app-store against App Store Connect limits.

A field is a heading "## <Field> (<count> / <limit>)" followed by a ```text block.
Screenshot captions are rows of the table whose last column is "Chars".

  python3 docs/app-store/check-listing.py         # check, exit 1 on any problem
  python3 docs/app-store/check-listing.py --fix   # rewrite the stated counts, then check
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIELD_FILES = ["listing.md", "review-notes.md"]
PUBLIC_FILES = ["privacy-policy.md", "terms-of-use.md"]
CAPTION_LIMIT = 40

# Terms that must not appear in customer-facing copy.
BANNED = [
    r"android", r"pixel", r"google", r"now playing", r"samsung", r"windows",
    r"sounds?", r"ringtones?",  # per-app sounds are not in 1.0
    r"best", r"ultimate", r"amazing", r"revolutionary", r"#1",
]
BANNED_RE = re.compile(r"(?<![\w#])(" + "|".join(BANNED) + r")(?!\w)", re.IGNORECASE)

HEADING_RE = re.compile(r"^## (?P<field>.+?) \((?P<count>[\d,]+) / (?P<limit>[\d,]+)\)$", re.MULTILINE)
BLOCK_RE = re.compile(r"```text\n(?P<body>.*?)\n```", re.DOTALL)
CAPTION_ROW_RE = re.compile(r"^\| (?P<n>\d+) \| (?P<screen>[^|]+) \| (?P<caption>[^|]+?) \| (?P<chars>\d+) \|$", re.MULTILINE)


def num(s):
    return int(s.replace(",", ""))


def fields(text):
    heads = list(HEADING_RE.finditer(text))
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        nxt = text.find("\n## ", h.end())
        if nxt != -1:
            end = min(end, nxt)
        block = BLOCK_RE.search(text, h.end(), end)
        yield h, block


def banned(body):
    return sorted({m.group(1).lower() for m in BANNED_RE.finditer(body)})


def main():
    fix = "--fix" in sys.argv
    problems = []
    rows = []

    for name in FIELD_FILES:
        path = HERE / name
        text = path.read_text()
        if fix:
            def put_count(h):
                block = BLOCK_RE.search(text, h.end())
                return f"## {h.group('field')} ({len(block.group('body')):,} / {h.group('limit')})"
            text = HEADING_RE.sub(put_count, text)
            text = CAPTION_ROW_RE.sub(
                lambda m: f"| {m['n']} | {m['screen']} | {m['caption']} | {len(m['caption'])} |", text)
            path.write_text(text)

        for h, block in fields(text):
            label = f"{name}: {h.group('field')}"
            if block is None:
                problems.append(f"{label}: no ```text block under the heading")
                continue
            body = block.group("body")
            actual, stated, limit = len(body), num(h.group("count")), num(h.group("limit"))
            ok = actual == stated and actual <= limit
            rows.append((label, actual, limit))
            if actual != stated:
                problems.append(f"{label}: states {stated} characters, actually {actual}")
            if actual > limit:
                problems.append(f"{label}: {actual} characters, over the {limit} limit")
            if not body.isascii():
                bad = sorted({c for c in body if not c.isascii()})
                problems.append(f"{label}: non-ASCII characters {bad}")
            if h.group("field") == "Keywords":
                if ", " in body or body != body.strip():
                    problems.append(f"{label}: use commas with no spaces")
                words = body.split(",")
                if len(words) != len(set(words)):
                    problems.append(f"{label}: repeated keyword")
            for term in banned(body):
                problems.append(f"{label}: banned term '{term}'")

        for m in CAPTION_ROW_RE.finditer(text):
            caption = m.group("caption")
            label = f"{name}: screenshot {m.group('n')} caption"
            rows.append((label, len(caption), CAPTION_LIMIT))
            if len(caption) != int(m.group("chars")):
                problems.append(f"{label}: states {m.group('chars')} characters, actually {len(caption)}")
            if len(caption) > CAPTION_LIMIT:
                problems.append(f"{label}: over {CAPTION_LIMIT} characters")
            for term in banned(caption):
                problems.append(f"{label}: banned term '{term}'")

    for name in PUBLIC_FILES:
        for term in banned((HERE / name).read_text()):
            if term in ("android", "pixel", "google", "now playing", "samsung", "windows"):
                problems.append(f"{name}: other-platform or brand term '{term}'")

    width = max(len(r[0]) for r in rows)
    for label, actual, limit in rows:
        print(f"{label:<{width}}  {actual:>5,} / {limit:,}")
    if problems:
        print("\nProblems:")
        for p in problems:
            print(f"- {p}")
        return 1
    print("\nAll fields within limits, counts match, no banned terms.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
