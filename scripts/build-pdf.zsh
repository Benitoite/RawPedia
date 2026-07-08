#!/bin/zsh
set -euo pipefail

RAWPEDIA_ROOT="$HOME/RawPedia"
PUBLIC_DIR="$RAWPEDIA_ROOT/Public"
CONTENTS_DIR="$RAWPEDIA_ROOT/content"
WORK_DIR="rawtherapee-manual"
OUTPUT_HTML="$WORK_DIR/book.html"
OUTPUT_PDF="rawtherapee_manual.pdf"
RT_COVER_ICNS="$HOME/repo-rt/tools/osx/rawtherapee.icns"
RT_COVER_PNG="$WORK_DIR/rawtherapee-cover-icon.png"

RT_HEADER_ICO="$HOME/repo-rt/rtdata/images/rawtherapee.ico"
RT_HEADER_PNG="$WORK_DIR/rawtherapee-header-icon.png"

RAWPEDIA_QR_SVG="$WORK_DIR/rawpedia-online-qr.svg"
RAWPEDIA_ONLINE_URL="https://rawpedia.pixls.us"

RT_AUTHORS_TXT="$HOME/repo-rt/AUTHORS.txt"

RT_GIT_DIR="$HOME/repo-rt"

GPLV3_LOGO_SVG="$WORK_DIR/gplv3-logo.svg"
GPLV3_LOGO_URL="https://upload.wikimedia.org/wikipedia/commons/9/93/GPLv3_Logo.svg"

BOOK_BASE_URL="https://rawpedia.pixls.us"

print_step() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_step "📖 Building RawTherapee PDF manual..."

if ! command -v hugo &> /dev/null; then
  print_step "❌ hugo not found"
  exit 1
fi

if ! command -v python3 &> /dev/null; then
  print_step "❌ python3 not found"
  exit 1
fi

if ! command -v weasyprint &> /dev/null; then
  print_step "❌ weasyprint not found. Install with: pip3 install weasyprint"
  exit 1
fi

if [ ! -d "$RAWPEDIA_ROOT" ]; then
  print_step "❌ RAWPEDIA_ROOT not found: $RAWPEDIA_ROOT"
  exit 1
fi

git_version_string() {
  pushd "$RT_GIT_DIR" > /dev/null 2>&1

  version=$(git describe --tags --abbrev=8 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

  popd > /dev/null 2>&1

  echo "$version ($branch)"
}

sanitize_hrefs_for_weasyprint() {
  python3 - "$1" <<'SANITIZE_HREF'
import re
import sys
from pathlib import Path

html = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

html = re.sub(r'href="data:text/html[^"]*"', 'href="#"', html, flags=re.I)

html = re.sub(r'href="javascript:[^"]*"', 'href="#"', html, flags=re.I)

Path(sys.argv[1]).write_text(html, encoding="utf-8")
SANITIZE_HREF
}

cd "$RAWPEDIA_ROOT"

print_step "🔄 Running Hugo..."

hugo --contentDir "$CONTENTS_DIR" --destination "$WORK_DIR" --baseURL "$BOOK_BASE_URL" --disableKinds page

print_step "🧹 Cleaning up Hugo build artifacts..."

find "$WORK_DIR" -name ".DS_Store" -delete
find "$WORK_DIR" -name "Thumbs.db" -delete
find "$WORK_DIR" -name "feed.xml" -delete
find "$WORK_DIR" -name "sitemap.xml" -delete
find "$WORK_DIR" -name "robots.txt" -delete

print_step "📥 Downloading external assets..."

# GPLv3 logo
if [ ! -f "$GPLV3_LOGO_SVG" ]; then
  echo "Fetching GPLv3 logo..."
  curl -s --max-time 10 "$GPLV3_LOGO_URL" -o "$GPLV3_LOGO_SVG" || true
fi

# RT cover icon
if [ -f "$RT_COVER_ICNS" ] && ! [ -f "$RT_COVER_PNG" ]; then
  echo "Converting RT cover icon (ICNS to PNG)..."
  sips -s format png "$RT_COVER_ICNS" --out "$RT_COVER_PNG" 2>/dev/null || true
fi

# RT header icon
if [ -f "$RT_HEADER_ICO" ] && ! [ -f "$RT_HEADER_PNG" ]; then
  echo "Converting RT header icon (ICO to PNG)..."
  ffmpeg -i "$RT_HEADER_ICO" "$RT_HEADER_PNG" -y >/dev/null 2>&1 || true
fi

# Fallback: create placeholder if conversion failed
if ! [ -f "$RT_HEADER_PNG" ]; then
  python3 << 'CREATE_FALLBACK_PNG'
from PIL import Image
import sys

try:
    img = Image.new('RGBA', (256, 256), (200, 200, 200, 255))
    img.save("rawtherapee-manual/rawtherapee-header-icon.png")
except Exception:
    pass
CREATE_FALLBACK_PNG
fi

# RawPedia online QR code
python3 - "$RAWPEDIA_ONLINE_URL" "$RAWPEDIA_QR_SVG" <<'GENERATE_QR'
import sys
try:
    import qrcode
    import qrcode.image
    url = sys.argv[1]
    path = sys.argv[2]
    qr = qrcode.QRCode(version=1, box_size=8, border=1)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save(path)
except ImportError:
    print("⚠️ qrcode not found; skipping RawPedia online QR code")
except Exception as e:
    print(f"⚠️ QR code generation failed: {e}")
GENERATE_QR

print_step "📝 Building PDF book structure..."

python3 - "$WORK_DIR" "$CONTENTS_DIR" "$OUTPUT_HTML" "$RT_COVER_PNG" "$RT_HEADER_PNG" "$GPLV3_LOGO_SVG" "$RAWPEDIA_QR_SVG" "$RT_AUTHORS_TXT" "$RT_GIT_DIR" <<'BUILD_BOOK'
import re
import os
import sys
import json
import html
import urllib.parse
from pathlib import Path
from typing import List, Set, Dict, Optional, Tuple
from html.parser import HTMLParser

WORK_DIR = Path(sys.argv[1]).resolve()
CONTENTS_DIR = Path(sys.argv[2]).resolve()
OUTPUT_HTML = Path(sys.argv[3]).resolve()
RT_COVER_PNG = Path(sys.argv[4]).resolve()
RT_HEADER_PNG = Path(sys.argv[5]).resolve()
GPLV3_LOGO_SVG = Path(sys.argv[6]).resolve()
RAWPEDIA_QR_SVG = Path(sys.argv[7]).resolve()
RT_AUTHORS_TXT = Path(sys.argv[8]).resolve()
RT_GIT_DIR = Path(sys.argv[9]).resolve()

SOURCE_DIR = WORK_DIR.parent

asset_exts = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".tif", ".tiff", ".bmp", ".ico"}
metadata_exts = {".md", ".markdown", ".html"}

language_codes = {
    "en", "fr", "es", "it", "jp", "ja", "pt", "de", "ca", "ct", "zh", "cn", "ru", "nl", "pl", "tr",
}

missing_images = []
asset_by_name = {}
suppressed_redirects = []
suppressed_main_pages = []
all_contributors = set()

for root, dirs, files in os.walk(SOURCE_DIR):
    for name in files:
        p = Path(root) / name
        if p.suffix.lower() in asset_exts:
            asset_by_name.setdefault(name.lower(), p.resolve())

def rel_from_source(path: Path) -> str:
    try:
        return str(path.relative_to(SOURCE_DIR))
    except ValueError:
        return str(path)

def make_id(rel: str) -> str:
    rel = html.unescape(rel or "")
    rel = urllib.parse.unquote(rel)
    rel = rel.replace("\\", "/")

    rel = re.sub(r"/index\.html$", "", rel, flags=re.I)
    rel = re.sub(r"\.html$", "", rel, flags=re.I)
    rel = re.sub(r"\.(md|markdown)$", "", rel, flags=re.I)

    rel = rel.strip("/")
    rel = rel.replace("_", "-")
    rel = re.sub(r"[^a-z0-9/-]+", "-", rel.lower())
    rel = rel.replace("/", "-")
    rel = re.sub(r"-+", "-", rel)

    return rel.strip("-")

used_term_ids = {}

def term_id(term: str) -> str:
    base = "index-" + re.sub(r"[^A-Za-z0-9]+", "-", term).strip("-").lower()
    base = base or "index-term"

    count = used_term_ids.get(base, 0)
    used_term_ids[base] = count + 1

    if count == 0:
        return base

    return f"{base}-{count + 1}"

def section_toc_id(section: str) -> str:
    return "toc-" + make_id(section)

def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")

def html_to_plain_text(s: str) -> str:
    s = re.sub(r"<script\b.*?</script>", " ", s, flags=re.I | re.S)
    s = re.sub(r"<style\b.*?</style>", " ", s, flags=re.I | re.S)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    return s

def strip_empty_leading_blocks(s: str) -> str:
    """
    Avoid blankies at article starts.

    Some generated pages begin with empty wrappers, hidden anchors, empty figures,
    or website furniture. When those are the first content inside a forced article
    page, WeasyPrint can reserve/push space and leave blank pages before real text.
    """
    changed = True

    empty_block = re.compile(
        r"""(?is)^\s*
        (?:
            <(?:div|section|article|aside|figure|header|footer)\b[^>]*>\s*</(?:div|section|article|aside|figure|header|footer)> |
            <(?:a|span|p)\b[^>]*>\s*</(?:a|span|p)> |
            <(?:a|span)\b[^>]*\s+(?:id|name)=[^>]*>\s*</(?:a|span)> |
            <!--.*?--> |
            <br\s*/?> |
            <img\b[^>]*?\s(?:hidden|style=[^>]*\bhidden)\b[^>]*>
        )
        """
    )

    while changed:
        old_s = s
        s = empty_block.sub("", s)
        changed = len(s) < len(old_s)

    return s

def content_rel_is_probably_english(rel: str) -> bool:
    """
    Return False for Hugo translation files and language-directory content.

    Examples suppressed:
      fr/foo.md
      es/foo.md
      foo.fr.md
      foo.es.md
      foo/index.fr.md
      _index.fr.md

    Examples allowed:
      MacOS.md
      Keyboard_Shortcuts.md
      local-adjustments/index.md
    """
    rel = rel.replace("\\", "/").strip("/")
    rel_lower = rel.lower()
    parts = rel_lower.split("/")

    if parts and parts[0] in language_codes:
        return False

    name = Path(rel_lower).name

    # Remove final content extension.
    base = re.sub(r"\.(md|markdown|html)$", "", name, flags=re.I)

    # Hugo multilingual filenames: article.fr.md, index.de.md, _index.es.md
    if "." in base:
        suffix = base.rsplit(".", 1)[-1]
        if suffix in language_codes:
            return False

    # Also catch underscore/dash language suffixes sometimes used by migrations.
    if re.search(
        r"(^|[-_.])(fr|es|it|jp|ja|pt|de|ca|ct|zh|cn|ru|nl|pl|tr)$",
        base,
        flags=re.I,
    ):
        return False

    return True

def extract_frontmatter_string_field(fm: str, field: str) -> str:
    m = re.search(
        rf"^\s*{re.escape(field)}\s*[:=]\s*['\"]?([^'\"\n#]+)['\"]?\s*$",
        fm,
        flags=re.I | re.M,
    )

    if not m:
        return ""

    return m.group(1).strip()

def extract_frontmatter_list_field(fm: str, field: str) -> List[str]:
    out = []

    m = re.search(
        rf"^\s*{re.escape(field)}\s*[:=]\s*(.*?)\s*$",
        fm,
        flags=re.I | re.M,
    )

    if not m:
        return out

    rest = m.group(1).strip()

    if rest.startswith("[") and rest.endswith("]"):
        out.extend(x.strip() for x in re.findall(r'["\']([^"\']+)["\']', rest))
        return out

    if rest and rest not in {"|", ">"}:
        out.append(rest.strip().strip('"\''))
        return out

    lines = fm.splitlines()
    start = None

    for i, line in enumerate(lines):
        if re.match(rf"^\s*{re.escape(field)}\s*[:=]\s*$", line, flags=re.I):
            start = i + 1
            break

    if start is None:
        return out

    for line in lines[start:]:
        if not line.strip():
            continue

        if re.match(r"^\S", line):
            break

        lm = re.match(r"^\s*-\s*(.*?)\s*$", line)
        if lm:
            out.append(lm.group(1).strip().strip('"\''))

    return out

def content_file_redirect_target_quick(path: Path) -> str:
    try:
        text = read_text(path)
    except Exception:
        return ""

    return extract_redirect_target_from_source_text(text)

def content_file_is_redirect_quick(path: Path) -> bool:
    return bool(content_file_redirect_target_quick(path))

def content_lookup_key(key: str) -> str:
    key = html.unescape(key or "").strip()
    key = urllib.parse.unquote(key)
    key = key.replace("\\", "/").lower()
    key = re.sub(r"/index\.html?$", "", key, flags=re.I)
    key = re.sub(r"\.html?$", "", key, flags=re.I)
    key = re.sub(r"\.(md|markdown)$", "", key, flags=re.I)
    key = key.strip("/")
    key = re.sub(r"\s+", " ", key)
    return key

def build_content_file_index() -> Dict:
    """
    Build route/alias/url/title lookup -> actual CONTENTS_DIR file path.
    """
    index = {}

    if not CONTENTS_DIR.exists():
        return index

    def add(key: str, path: Path):
        key = content_lookup_key(key)

        if not key:
            return

        existing = index.get(key)

        if existing is None:
            index[key] = path
            return

        existing_is_redirect = content_file_is_redirect_quick(existing)
        new_is_redirect = content_file_is_redirect_quick(path)

        if existing_is_redirect and not new_is_redirect:
            index[key] = path
            return

    for root, dirs, files in os.walk(CONTENTS_DIR):
        for name in files:
            p = Path(root) / name

            if p.suffix.lower() not in {".md", ".markdown", ".html"}:
                continue

            if not content_rel_is_probably_english(rel_from_source(p)):
                continue

            rel = str(p.relative_to(CONTENTS_DIR)).replace("\\", "/")

            add(rel, p)
            add(rel.replace("/index", ""), p)
            add(rel.replace(".md", ".html"), p)
            add(rel.replace(".markdown", ".html"), p)

            fm = extract_hugo_frontmatter(read_text(p))
            title = extract_frontmatter_string_field(fm, "title").strip()
            if title:
                add(title, p)
                add(make_id(title), p)

            for alias in extract_aliases_from_content_file(p):
                add(alias, p)
                add(make_id(alias), p)

    for key, path in list(index.items()):
        index[content_lookup_key(key.replace("/", "-"))] = path
        index[content_lookup_key(key.replace("/", "_"))] = path
        index[content_lookup_key(key.replace("-", "_"))] = path
        index[content_lookup_key(key.replace("_", "-"))] = path

    return index

content_file_index = build_content_file_index()

def extract_hugo_frontmatter(text: str) -> str:
    if not text.startswith("---"):
        return ""

    rest = text[3:]
    match = re.search(r"^---\s*$", rest, flags=re.M)

    if not match:
        return ""

    return rest[:match.start()]

def extract_aliases_from_content_file(path: Optional[Path]) -> List[str]:
    if not path or not path.exists():
        return []

    text = read_text(path)
    fm = extract_hugo_frontmatter(text)

    if not fm:
        return []

    aliases = []
    lines = fm.splitlines()

    i = 0
    while i < len(lines):
        line = lines[i]

        m = re.match(r"^\s*aliases\s*[:=]\s*(.*?)\s*$", line, flags=re.I)
        if not m:
            i += 1
            continue

        rest = m.group(1).strip()

        if rest.startswith("[") and rest.endswith("]"):
            for item in re.findall(r'["\']([^"\']+)["\']', rest):
                aliases.append(item.strip())
            i += 1
            continue

        if rest and rest not in {"|", ">"}:
            aliases.append(rest.strip().strip('"\''))
            i += 1
            continue

        i += 1
        while i < len(lines):
            child = lines[i]

            if not child.strip():
                i += 1
                continue

            if re.match(r"^\S", child):
                break

            m = re.match(r"^\s*-\s*(.*?)\s*$", child)
            if m:
                aliases.append(m.group(1).strip().strip('"\''))

            i += 1

        break

    return aliases

def extract_redirect_target_from_source_text(text: str) -> str:
    """
    Extract the redirect target from Hugo aliases or redirectFrom.
    """
    fm = extract_hugo_frontmatter(text)

    # Check for 'redirectTo' or 'redirect' fields
    redirect_to = extract_frontmatter_string_field(fm, "redirectTo")
    if redirect_to:
        return redirect_to

    redirect_field = extract_frontmatter_string_field(fm, "redirect")
    if redirect_field:
        return redirect_field

    # Check for HTML meta refresh
    m = re.search(r'<meta\s+http-equiv=["\']refresh["\'][^>]*content=["\']([^;]*)', text, flags=re.I | re.S)
    if m:
        return m.group(1).strip()

    return ""

def extract_contributors_from_hugo_frontmatter(text: str) -> Set[str]:
    contributors = set()
    fm = extract_hugo_frontmatter(text)

    if not fm:
        return contributors

    lines = fm.splitlines()

    i = 0
    while i < len(lines):
        line = lines[i]

        m = re.match(r"^\s*(contributors?|authors?|creator)\s*[:=]\s*(.*?)\s*$", line, flags=re.I)
        if not m:
            i += 1
            continue

        rest = m.group(2).strip()

        if rest.startswith("[") and rest.endswith("]"):
            for item in re.findall(r'["\']([^"\']+)["\']', rest):
                for name in split_contributor_field(item):
                    contributors.add(name)
            i += 1
            continue

        if rest and rest not in {"|", ">"}:
            for name in split_contributor_field(rest):
                contributors.add(name)
            i += 1
            continue

        i += 1
        while i < len(lines):
            child = lines[i]

            if not child.strip():
                i += 1
                continue

            if re.match(r"^\S", child):
                break

            m = re.match(r"^\s*-\s*(.*?)\s*$", child)
            if m:
                for name in split_contributor_field(m.group(1)):
                    contributors.add(name)

            i += 1

        break

    return contributors

def clean_person_name(name: str) -> str:
    blocked = {
        "rtadmin",
        "example",
        "john-doe",
        "john_doe",
        "user",
        "user1",
        "contributor",
        "contributors",
        "rawpedia contributors",
        "the rawtherapee development team",
        "rawtherapee development team",
        "contributors",
        "contributor",
        "author",
        "authors",
        "metadata",
        "none",
        "null",
        "true",
        "false",
    }

    if name.lower() in blocked:
        return ""

    if len(name) > 80:
        return ""

    if re.search(r"https?://|@type|@context|\.css|\.js|\.html", name, flags=re.I):
        return ""

    return name

def split_contributor_field(value: str) -> List[str]:
    value = html.unescape(value or "").strip()

    if not value:
        return []

    value = re.sub(r"\s+", " ", value)
    jsonish = value.strip()

    if jsonish.startswith("[") and jsonish.endswith("]"):
        try:
            decoded = json.loads(jsonish.replace("'", '"'))
            out = []
            if isinstance(decoded, list):
                for item in decoded:
                    if isinstance(item, str):
                        out.extend(split_contributor_field(item))
                    elif isinstance(item, dict):
                        for k in ("name", "author", "contributor"):
                            if k in item:
                                out.extend(split_contributor_field(str(item[k])))
                return out
        except Exception:
            value = jsonish.strip("[]")

    value = value.strip("[](){} ")
    parts = re.split(r"\s*(?:,|;|\||\band\b|\&)\s*", value, flags=re.I)

    cleaned = []

    for part in parts:
        p = clean_person_name(part)
        if p:
            cleaned.append(p)

    return cleaned

def extract_contributors_from_metadata(text: str) -> Set[str]:
    contributors = set()

    for name in extract_contributors_from_hugo_frontmatter(text):
        contributors.add(name)

    meta_tags = re.findall(r"<meta\b[^>]*>", text, flags=re.I | re.S)

    for tag in meta_tags:
        name_match = re.search(
            r'\b(?:name|property|itemprop)=["\']([^"\']+)["\']',
            tag,
            flags=re.I | re.S,
        )
        content_match = re.search(
            r'\bcontent=["\']([^"\']*)["\']',
            tag,
            flags=re.I | re.S,
        )

        if not name_match or not content_match:
            continue

        key = html.unescape(name_match.group(1)).strip().lower()
        value = content_match.group(1)

        if key in {
            "author", "authors", "contributor", "contributors",
            "page:author", "page:authors", "page:contributor", "page:contributors",
            "article:author", "article:authors", "article:contributor", "article:contributors",
        }:
            for name in split_contributor_field(value):
                contributors.add(name)

    for script in re.findall(
        r"<script\b[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>",
        text,
        flags=re.I | re.S,
    ):
        try:
            data = json.loads(html.unescape(script.strip()))
        except Exception:
            data = None

        def walk_json(obj):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    lk = str(key).lower()
                    if lk in {"author", "authors", "contributor", "contributors", "creator"}:
                        if isinstance(value, str):
                            for name in split_contributor_field(value):
                                contributors.add(name)
                        elif isinstance(value, dict):
                            if "name" in value:
                                for name in split_contributor_field(str(value["name"])):
                                    contributors.add(name)
                            walk_json(value)
                        elif isinstance(value, list):
                            for item in value:
                                walk_json(item)
                    else:
                        walk_json(value)
            elif isinstance(obj, list):
                for item in obj:
                    walk_json(item)

        if data is not None:
            walk_json(data)

    return contributors

def harvest_contributors_from_contents() -> Set[str]:
    found = set()

    if not CONTENTS_DIR.exists():
        return found

    scanned = 0

    for root, dirs, files in os.walk(CONTENTS_DIR):
        for name in files:

            p = Path(root) / name

            if p.suffix.lower() not in metadata_exts:
                continue

            try:
                text = read_text(p)
            except Exception:
                continue

            scanned += 1

            for contributor in extract_contributors_from_metadata(text):
                found.add(contributor)

    print(f"Hugo source metadata files scanned: {scanned}")
    return found

def read_authors_file() -> List[str]:
    if not RT_AUTHORS_TXT.exists():
        return []

    names = []
    text = read_text(RT_AUTHORS_TXT)

    for line in text.splitlines():
        line = line.strip()

        if not line or line.startswith("#"):
            continue

        name = clean_person_name(line)
        if name:
            names.append(name)

    return names

def extract_title_from_html_file(path: Path) -> str:
    text = read_text(path)

    fm = extract_hugo_frontmatter(text)
    title = extract_frontmatter_string_field(fm, "title")

    if title:
        return title

    m = re.search(r"<title\b[^>]*>(.*?)</title>", text, flags=re.I | re.S)
    if m:
        return html_to_plain_text(m.group(1))

    m = re.search(r"<h1\b[^>]*>(.*?)</h1>", text, flags=re.I | re.S)
    if m:
        return html_to_plain_text(m.group(1))

    return ""

def extract_heading_terms(content: str) -> Set[str]:
    terms = set()

    for m in re.finditer(r"<h[1-4]\b[^>]*>(.*?)</h[1-4]>", content, flags=re.I | re.S):
        heading = html_to_plain_text(m.group(1))
        heading = re.sub(r"\s+", " ", heading).strip()

        if 2 <= len(heading) <= 70:
            terms.add(heading)

    return terms

def extract_title_terms(title: str) -> Set[str]:
    title = html.unescape(title).strip()
    out = set()

    if 2 <= len(title) <= 70:
        out.add(title)

    pieces = re.split(r"\s*(?:/|:|—|–|-|\(|\)|,)\s*", title)

    for p in pieces:
        p = re.sub(r"\s+", " ", p).strip()

        if 2 <= len(p) <= 70:
            out.add(p)

    return out

def clean_links(s: str) -> str:
    s = re.sub(r'href="[^"]*"', lambda m: m.group(0), s)
    return s

def page_is_probably_english_language(title: str, text: str) -> bool:
    title_key = make_id(title).lower()

    translated_title_words = [
        "fr", "es", "it", "de", "ca", "pt", "ru", "ja", "jp", "zh", "cn", "pl",
        "francais", "español", "italiano", "deutsch", "português", "русский", "日本語", "中文", "polski",
        "français", "español", "italiano", "português", "language", "sprache", "langue", "idioma", "lingua",
        "translation", "traduza", "traduzione", "übersetzung", "traduction", "profundidad", "contribuir", "compilando", "descàrrega", "baixar",
    ]

    if any(word in title_key for word in translated_title_words):
        return False

    sample = html.unescape(re.sub(r"<[^>]+>", " ", text[:16000])).lower()

    non_english_clues = [
        "table des matières", "sommaire", "premiers pas", "utilisation",
        "réglages", "généralités", "questo", "questa", "strumento",
        "elaborazione", "descargar", "opciones", "ajustes", "herramienta",
        "preferencias", "procesamiento", "índice", "tabla de contenidos",
    ]

    hits = sum(1 for clue in non_english_clues if clue in sample)

    if hits >= 2:
        return False

    return True

print("Building book from Hugo output...")
print(f"Work directory: {WORK_DIR}")

print("Done!")
BUILD_BOOK

sanitize_hrefs_for_weasyprint "$OUTPUT_HTML"

print_step "🎨 Rendering PDF (this may take a few minutes)..."

weasyprint \
  --base-url "$BOOK_BASE_URL" \
  --verbose \
  "$OUTPUT_HTML" \
  "$OUTPUT_PDF"

echo
echo
echo "🔗 Checking PDF link actions..."

python3 - "$OUTPUT_PDF" <<'CHECK_PDF_LINK_ACTIONS'
import sys
import subprocess
import json
from pathlib import Path

pdf = Path(sys.argv[1])

try:
    result = subprocess.run(
        ["qpdf", "--json", "--json-key=pages", str(pdf)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
except FileNotFoundError:
    print("⚠️ qpdf not found; skipping PDF link-action check.")
    sys.exit(0)
except subprocess.CalledProcessError as e:
    print("⚠️ qpdf link-action check failed; skipping.")
    print(e.stderr[:1000])
    sys.exit(0)

data = json.loads(result.stdout)

uri_count = 0
goto_count = 0
other_count = 0
samples = []

def walk(obj):
    global uri_count, goto_count, other_count
    if not isinstance(obj, dict):
        if isinstance(obj, list):
            for item in obj:
                walk(item)
        return

    if "A" in obj:
        annot = obj["A"]
        if isinstance(annot, dict):
            s = annot.get("S")
            if s == "/URI":
                uri_count += 1
                uri = annot.get("URI", "")
                if len(samples) < 5:
                    samples.append(f"  URI: {uri}")
            elif s == "/GoTo":
                goto_count += 1
                if len(samples) < 5:
                    samples.append(f"  GoTo: {annot.get('D', 'unknown')}")
            else:
                other_count += 1
                if len(samples) < 5:
                    samples.append(f"  {s}")

    for key, value in obj.items():
        walk(value)

walk(data)

print(f"  URI links: {uri_count}")
print(f"  Internal (GoTo) links: {goto_count}")
print(f"  Other link types: {other_count}")

if samples:
    print("\n  Sample links:")
    for sample in samples:
        print(sample)

if uri_count + goto_count == 0:
    print("\n⚠️ Warning: No actionable links found in PDF!")

CHECK_PDF_LINK_ACTIONS

print_step "✅ PDF generation complete!"

if [ -f "$OUTPUT_PDF" ]; then
  size=$(du -h "$OUTPUT_PDF" | cut -f1)
  echo "📄 Output: $OUTPUT_PDF ($size)"
fi
