#!/usr/bin/env python3
"""Check maintained documentation navigation without Swift, Xcode, or network access.

Covers inline Markdown links/images, reference links, GitHub-style heading anchors,
and DocC article links. Same-repository main URLs resolve against this checkout.
DocC symbols, remote URLs, and historical research/release bodies are out of scope.
"""

import argparse
import html
from pathlib import Path
import re
import string
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
ENTRY_FILES = (
    "AGENTS.md", "CONTRIBUTING.md", "DESIGN.md", "README.md", "llms.txt",
    "docs/Research/README.md",
)
GUIDE_GLOBS = (
    "docs/*.md", "docs/agents/**/*.md", "docs/guides/**/*.md",
    "Sources/Aski/Aski.docc/**/*.md",
)
REPO_PREFIXES = (
    ("raw.githubusercontent.com", "/BigCactusLabs/Aski/main/"),
    ("github.com", "/BigCactusLabs/Aski/blob/main/"),
    ("github.com", "/BigCactusLabs/Aski/tree/main/"),
)
# One level of balanced parentheses covers current filenames and URL destinations.
DESTINATION = r"(<[^>\n]+>|(?:\\.|[^\s()\\]|\([^()\n]*\))+)"
INLINE_LINK = re.compile(r"!?\[[^\]\n]*\]\(\s*" + DESTINATION + r"(?:\s+[\"'][^\n]*?[\"'])?\s*\)")
REFERENCE = re.compile(r"^ {0,3}\[([^\]\n]+)\]:\s*" + DESTINATION, re.MULTILINE)
REFERENCE_USE = re.compile(r"!?\[([^\]\n]+)\]\[([^\]\n]*)\]")
ARTICLE = re.compile(r"<doc:([^>\n]+)>")
MARKDOWN_ESCAPE = re.compile(r"\\([" + re.escape(string.punctuation) + r"])")


def is_escaped(text, index):
    backslashes = 0
    while index > 0 and text[index - 1] == "\\":
        backslashes += 1
        index -= 1
    return backslashes % 2 == 1


def reference_label(label):
    # CommonMark reference labels ignore case and collapse whitespace runs.
    return " ".join(label.split()).casefold()


def destination_text(value):
    return html.unescape(MARKDOWN_ESCAPE.sub(r"\1", value.strip("<>")))


def visible_markdown(text):
    """Blank code/comments without moving line numbers; preserve heading contents."""
    output = []
    fence = None
    in_comment = False
    for line in text.splitlines(keepends=True):
        if fence:
            output.append("\n" if line.endswith("\n") else "")
            marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line.rstrip("\r\n"))
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= fence[1] and not marker[2].strip():
                fence = None
            continue
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line.rstrip("\r\n"))
        if not in_comment and marker:
            fence = (marker[1][0], len(marker[1]))
            output.append("\n" if line.endswith("\n") else "")
            continue

        # Comments can contain fenced examples. Strip them before looking for an
        # opening fence, but never interpret comment markers inside fenced code.
        visible = []
        cursor = 0
        comment_line = without_inline_code(line)
        while cursor < len(line):
            marker = "-->" if in_comment else "<!--"
            index = (line if in_comment else comment_line).find(marker, cursor)
            end = len(line) if index < 0 else index + len(marker)
            if in_comment:
                visible.append(re.sub(r"[^\r\n]", " ", line[cursor:end]))
            elif index < 0:
                visible.append(line[cursor:end])
            else:
                visible.append(line[cursor:index] + " " * len(marker))
            cursor = end
            if index >= 0:
                in_comment = not in_comment
        line = "".join(visible)
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line.rstrip("\r\n"))
        if marker:
            fence = (marker[1][0], len(marker[1]))
            output.append("\n" if line.endswith("\n") else "")
        else:
            output.append(line)
    return "".join(output)


def without_inline_code(text):
    return re.sub(r"(`+)([^`]|(?!\1)`)*?\1", lambda m: re.sub(r"[^\r\n]", " ", m[0]), text)


def heading_ids(text):
    text = visible_markdown(text)
    anchors = set(re.findall(r'<a\s+(?:[^>]*?\s)?(?:id|name)=["\']([^"\']+)["\']', text, re.IGNORECASE))
    lines = text.splitlines()
    for i, line in enumerate(lines):
        match = re.match(r"^ {0,3}#{1,6}\s+(.+?)(?:\s+#+)?\s*$", line)
        if match:
            title = match[1]
        elif re.fullmatch(r" {0,3}(?:=+|-+)\s*", line) and i and lines[i - 1].strip():
            title = lines[i - 1].strip()
        else:
            continue
        title = re.sub(r"!?\[([^]]*)\]\([^)]*\)", r"\1", title)
        title = re.sub(r"<[^>]*>", "", title)
        title = html.unescape(title).lower()
        slug = re.sub(r"[^\w\-\s]", "", title)
        slug = re.sub(r"\s", "-", slug)
        candidate = slug
        suffix = 0
        while candidate in anchors:
            suffix += 1
            candidate = f"{slug}-{suffix}"
        anchors.add(candidate)
    return anchors


def links(text):
    text = without_inline_code(visible_markdown(text))
    references = {reference_label(m[1]): m[2] for m in REFERENCE.finditer(text)}
    for match in INLINE_LINK.finditer(text):
        bracket = match.start() + (text[match.start()] == "!")
        if not is_escaped(text, bracket):
            yield text[:match.start()].count("\n") + 1, destination_text(match[1]), False
    for match in REFERENCE.finditer(text):
        yield text[:match.start()].count("\n") + 1, destination_text(match[2]), False
    for match in REFERENCE_USE.finditer(text):
        bracket = match.start() + (text[match.start()] == "!")
        if is_escaped(text, bracket):
            continue
        label = reference_label(match[2] or match[1])
        if label not in references:
            yield text[:match.start()].count("\n") + 1, f"undefined reference [{label}]", True
    for match in ARTICLE.finditer(text):
        if not is_escaped(text, match.start()):
            yield text[:match.start()].count("\n") + 1, destination_text("doc:" + match[1]), False


def local_target(source, destination, root):
    """Return (path, fragment), or None for a remote/symbol destination."""
    url = urlsplit(destination)
    if url.scheme == "doc":
        article = unquote(url.path)
        if not article.endswith(".md"):
            article += ".md"
        return source.parent / article, unquote(url.fragment)
    if url.scheme or url.netloc:
        for host, prefix in REPO_PREFIXES:
            if url.scheme in ("http", "https") and url.netloc == host and url.path.startswith(prefix):
                return root / unquote(url.path[len(prefix):]), unquote(url.fragment)
        return None
    path = unquote(url.path)
    if path.startswith("/"):
        return root / path.lstrip("/"), unquote(url.fragment)
    resolved = source.parent / path if path else source
    # DocC resolves an unqualified image name through the catalog's Resources/.
    if path and not resolved.exists() and Path(path).suffix.lower() in (".png", ".jpg", ".jpeg", ".gif", ".svg"):
        catalog = next((parent for parent in source.parents if parent.suffix == ".docc"), None)
        if catalog is not None and (catalog / "Resources" / path).exists():
            resolved = catalog / "Resources" / path
    return resolved, unquote(url.fragment)


def check_file(source, root, anchor_cache):
    failures = []
    checked = 0
    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return [f"{source.relative_to(root)}: cannot read file: {error}"], checked
    for line, destination, malformed in links(text):
        prefix = f"{source.relative_to(root)}:{line}"
        if malformed:
            failures.append(f"{prefix}: {destination}")
            continue
        target = local_target(source, destination, root)
        if target is None:
            continue
        checked += 1
        path, fragment = target
        path = path.resolve()
        try:
            path.relative_to(root)
        except ValueError:
            failures.append(f"{prefix}: target escapes repository: {destination}")
            continue
        if not path.exists():
            failures.append(f"{prefix}: missing target: {destination}")
        elif fragment and path.is_file() and path.suffix in (".md", ".txt"):
            if path not in anchor_cache:
                anchor_cache[path] = heading_ids(path.read_text(encoding="utf-8"))
            if fragment not in anchor_cache[path]:
                failures.append(f"{prefix}: missing heading #{fragment}: {destination}")
    return failures, checked


def documentation_files(root):
    files = {root / name for name in ENTRY_FILES}
    for pattern in GUIDE_GLOBS:
        files.update(root.glob(pattern))
    return sorted(files)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root (defaults to this script's checkout)")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    failures = []
    checked = 0
    anchor_cache = {}
    files = documentation_files(root)
    for source in files:
        errors, count = check_file(source, root, anchor_cache)
        failures.extend(errors)
        checked += count
    if failures:
        print("Documentation navigation failed:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"Documentation navigation passed: {len(files)} files, {checked} local links/article references.")
    print("Offline scope: maintained guides and entry points; native DocC symbols and remote URLs are not checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
