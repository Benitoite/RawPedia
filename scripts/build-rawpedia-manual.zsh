#!/bin/zsh
set -euo pipefail

SOURCE_DIR="$HOME/RawPedia/Public"
CONTENTS_DIR="$HOME/RawPedia/content"
WORK_DIR="rawpedia_book"
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

if [[ -d "$HOME/rawpedia/.git" ]]; then
  RAWPEDIA_GIT_DIR="$HOME/rawpedia"
else
  RAWPEDIA_GIT_DIR="$HOME/RawPedia"
fi

RT_LICENSE_TXT=""
for candidate in \
  "$HOME/repo-rt/LICENSE" \
  "$HOME/repo-rt/LICENSE.txt" \
  "$HOME/repo-rt/COPYING" \
  "$HOME/repo-rt/COPYING.txt"
do
  if [[ -f "$candidate" ]]; then
    RT_LICENSE_TXT="$candidate"
    break
  fi
done

mkdir -p "$WORK_DIR"

if [[ "${RAWPEDIA_KEEP_BOOK_CACHE:-0}" != "1" ]]; then
  echo "🧹 Cleaning old generated book reports and folders..."

  rm -f "$WORK_DIR/book.html"
  rm -f "$WORK_DIR"/*.txt(N)
  rm -f "$WORK_DIR"/*.svg(N)
  rm -f "$WORK_DIR"/*.png(N)
  rm -f "$WORK_DIR"/*.pdf(N)
  rm -f "$WORK_DIR"/*.json(N)
  rm -f "$WORK_DIR"/*.log(N)

  rm -rf "$WORK_DIR/article-qrs"
  rm -rf "$WORK_DIR/online-image-fallbacks"
else
  echo "🧹 Keeping old generated book cache because RAWPEDIA_KEEP_BOOK_CACHE=1"
fi

echo "📖 Building RawTherapee Manual..."

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "❌ SOURCE_DIR does not exist: $SOURCE_DIR"
  exit 1
fi

if [[ ! -d "$CONTENTS_DIR" ]]; then
  echo "⚠️ Hugo markdown source directory not found: $CONTENTS_DIR"
fi

if [[ ! -f "$RT_COVER_ICNS" ]]; then
  echo "❌ Cover .icns not found: $RT_COVER_ICNS"
  exit 1
fi

if [[ ! -f "$RT_HEADER_ICO" ]]; then
  echo "❌ Header .ico not found: $RT_HEADER_ICO"
  exit 1
fi

git_version_string() {
  local repo="$1"
  local label="$2"

  if [[ ! -d "$repo/.git" ]]; then
    echo "$label: no git repository found at $repo"
    return
  fi

  local branch describe dirty_marker

  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

  if [[ "$branch" == "HEAD" ]]; then
    branch="detached"
  fi

  describe="$(git -C "$repo" describe --tags --always 2>/dev/null || echo unknown)"

  if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
    dirty_marker="*"
  else
    dirty_marker=""
  fi

  echo "$label/$branch: $describe$dirty_marker"
}

RT_GIT_VERSION="$(git_version_string "$RT_GIT_DIR" "RawTherapee")"
RAWPEDIA_GIT_VERSION="$(git_version_string "$RAWPEDIA_GIT_DIR" "RawPedia")"

echo "✅ $RT_GIT_VERSION"
echo "✅ $RAWPEDIA_GIT_VERSION"

echo "🎨 Converting cover .icns icon..."

rm -f "$RT_COVER_PNG"

sips -s format png "$RT_COVER_ICNS" --out "$RT_COVER_PNG" >/dev/null

if [[ ! -s "$RT_COVER_PNG" ]]; then
  echo "❌ Failed to create cover PNG with sips: $RT_COVER_PNG"
  exit 1
fi

echo "🎨 Converting header .ico icon..."

rm -f "$RT_HEADER_PNG"
rm -f "$WORK_DIR"/rawtherapee-header-icon-*.png(N)

if command -v magick >/dev/null 2>&1; then
  ICO_SCENE="$(
    magick identify -format '%[scene] %[w] %[h]\n' "$RT_HEADER_ICO" 2>/dev/null \
      | awk '
          BEGIN { best_scene = 0; best_area = -1 }
          NF >= 3 {
            area = $2 * $3
            if (area > best_area) {
              best_area = area
              best_scene = $1
            }
          }
          END { print best_scene }
        '
  )"

  if [[ -z "$ICO_SCENE" ]]; then
    ICO_SCENE="0"
  fi

  echo "✅ Using header .ico frame: $ICO_SCENE"

  magick "${RT_HEADER_ICO}[$ICO_SCENE]" \
    -background none \
    -alpha on \
    -resize 192x192 \
    -gravity center \
    -extent 192x192 \
    "PNG32:$RT_HEADER_PNG"
else
  sips -s format png "$RT_HEADER_ICO" --out "$RT_HEADER_PNG" >/dev/null
fi

if [[ ! -s "$RT_HEADER_PNG" ]]; then
  echo "❌ Failed to create header PNG: $RT_HEADER_PNG"
  echo
  echo "Diagnostic:"
  if command -v magick >/dev/null 2>&1; then
    magick identify "$RT_HEADER_ICO" || true
  fi
  exit 1
fi

echo "🔳 Generating RawPedia QR code..."

if command -v qrencode >/dev/null 2>&1; then
  qrencode \
    -t SVG \
    -o "$RAWPEDIA_QR_SVG" \
    -m 1 \
    -s 10 \
    "$RAWPEDIA_ONLINE_URL"
else
  echo "❌ qrencode not found."
  echo "Install it with:"
  echo "brew install qrencode"
  exit 1
fi

if [[ ! -s "$RAWPEDIA_QR_SVG" ]]; then
  echo "❌ Failed to create QR code: $RAWPEDIA_QR_SVG"
  exit 1
fi

echo "🔎 Scanning generated HTML pages..."

find "$SOURCE_DIR" -type f -name "*.html" \
  ! -path "$SOURCE_DIR/index.html" \
  ! -path "$SOURCE_DIR/tags/*" \
  ! -path "$SOURCE_DIR/categories/*" \
  ! -path "$SOURCE_DIR/page/*" \
  | sort > "$WORK_DIR/pages-all.txt"

TOTAL_ALL=$(wc -l < "$WORK_DIR/pages-all.txt" | tr -d ' ')
echo "✅ Found $TOTAL_ALL total HTML pages"

echo "📚 Building book-style English manual..."

python3 - "$SOURCE_DIR" "$CONTENTS_DIR" "$WORK_DIR/pages-all.txt" "$OUTPUT_HTML" "$RT_COVER_PNG" "$RT_HEADER_PNG" "$RT_AUTHORS_TXT" "$RT_LICENSE_TXT" "$RT_GIT_VERSION" "$RAWPEDIA_GIT_VERSION" "$RAWPEDIA_QR_SVG" "$RAWPEDIA_ONLINE_URL" <<'PY'
import os
import re
import sys
import html
import json
import urllib.parse
import subprocess
from pathlib import Path
from datetime import datetime
from collections import defaultdict

SOURCE_DIR = Path(sys.argv[1]).expanduser().resolve()
CONTENTS_DIR = Path(sys.argv[2]).expanduser().resolve()
PAGES_ALL_TXT = Path(sys.argv[3])
OUTPUT_HTML = Path(sys.argv[4])

RT_COVER_PNG = Path(sys.argv[5]).resolve()
RT_HEADER_PNG = Path(sys.argv[6]).resolve()
RT_AUTHORS_TXT = Path(sys.argv[7]).expanduser()
RT_LICENSE_TXT = Path(sys.argv[8]).expanduser() if len(sys.argv) > 8 and sys.argv[8] else None

RT_GIT_VERSION = sys.argv[9] if len(sys.argv) > 9 else "RawTherapee: git version unavailable"
RAWPEDIA_GIT_VERSION = sys.argv[10] if len(sys.argv) > 10 else "RawPedia: git version unavailable"

RAWPEDIA_QR_SVG = Path(sys.argv[11]).resolve() if len(sys.argv) > 11 else None
RAWPEDIA_ONLINE_URL = sys.argv[12] if len(sys.argv) > 12 else "https://rawpedia.pixls.us"
RAWPEDIA_QR_URI = RAWPEDIA_QR_SVG.as_uri() if RAWPEDIA_QR_SVG and RAWPEDIA_QR_SVG.exists() else ""

RT_COVER_URI = RT_COVER_PNG.as_uri()
RT_HEADER_URI = RT_HEADER_PNG.as_uri()
BUILD_DATE = datetime.now().strftime("%Y-%m-%d")
COPYRIGHT_YEAR = datetime.now().strftime("%Y")

all_pages_raw = [
    Path(line.strip()).resolve()
    for line in PAGES_ALL_TXT.read_text().splitlines()
    if line.strip()
]

language_codes = {
    "fr", "es", "it", "jp", "ja", "pt", "de", "ca", "ct",
    "zh", "cn", "ru", "nl", "pl", "tr"
}

asset_exts = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp",
    ".tif", ".tiff", ".bmp", ".ico"
}

metadata_exts = {
    ".md", ".markdown", ".html", ".htm", ".yaml", ".yml",
    ".toml", ".json", ".txt"
}

technical_terms_seed = """
RawTherapee
RawPedia
RAW
Raw Black
Raw White
Raw Histogram
RawTherapee Processing Profile
Processing Profile
Dynamic Processing Profile
PP3
Sidecar File
Queue
Batch Editing
File Browser
Editor
Toolchain Pipeline
Pipeline
Demosaic
Demosaicing
AMaZE
RCD
LMMSE
VNG4
EAHD
HPHD
IGV
DCB
X-Trans
Bayer
Bayer Filter
Bayer Matrix
Color Filter Array
CFA
Hot Pixel
Dead Pixel
Bad Pixels
Dark Frame
Flat Field
Flat-Field Correction
Preprocessing
White Point
Black Point
Black Level
White Level
Clipping
Unclipped
Highlight Reconstruction
Highlight Compression
Exposure
Exposure Compensation
Auto Exposure
Auto Levels
Shadows
Highlights
Tone Curve
Tone Mapping
Retinex
Dynamic Range
HDR
Local Contrast
Microcontrast
Contrast
Brightness
Lightness
Luminance
Chrominance
Chromaticity
Saturation
Vibrance
Color Toning
Black-and-White
Channel Mixer
RGB Curves
Lab Adjustments
Local Adjustments
Spot Removal
Red Eye
Graduated Filter
Soft Light
Sharpening
Capture Sharpening
Post-Resize Sharpening
RL Deconvolution
Richardson-Lucy Deconvolution
Deconvolution
Unsharp Mask
High Pass
Edge Sharpness
Detail
Wavelet
Wavelets
Wavelet Levels
Noise
Noise Reduction
Denoise
Impulse Noise
Median Filter
Salt-and-Pepper Noise
Defringe
Chromatic Aberration
Lens Correction
Lens Profile
LCP
Distortion Correction
Perspective
Crop
Resize
Framing
Watermark
Vignetting
Vignette
Compression
Saving
Export
Output
Aperture
F-Number
F-Stop
T-Stop
Shutter Speed
Exposure Time
ISO
ISO Speed
Exposure Value
EV
Exposure Triangle
Metering
Spot Metering
Center-Weighted Metering
Matrix Metering
Evaluative Metering
Incident Metering
Reflected Metering
Middle Gray
18 Percent Gray
Gray Card
Zone System
Overexposure
Underexposure
Exposure Latitude
Reciprocity
Reciprocity Failure
Long Exposure
Bulb Exposure
Bracketing
Exposure Bracketing
HDR Merge
Fill Light
Backlighting
Silhouette
Specular Highlight
Diffuse Highlight
Shadow Detail
Highlight Detail
Camera
Lens
Prime Lens
Zoom Lens
Telephoto Lens
Wide-Angle Lens
Normal Lens
Macro Lens
Fisheye Lens
Tilt-Shift Lens
Lens Mount
Focal Length
Equivalent Focal Length
Crop Factor
Angle of View
Field of View
Image Circle
Entrance Pupil
Exit Pupil
Aperture Diaphragm
Iris
Focus
Autofocus
Manual Focus
Focus Peaking
Focus Stacking
Hyperfocal Distance
Depth of Field
Circle of Confusion
Bokeh
Lens Flare
Ghosting
Coma
Astigmatism
Spherical Aberration
Field Curvature
Barrel Distortion
Pincushion Distortion
Mustache Distortion
Lateral Chromatic Aberration
Longitudinal Chromatic Aberration
Axial Chromatic Aberration
Diffraction
Diffraction Limit
Airy Disk
Resolving Power
Resolution
Acutance
MTF
Modulation Transfer Function
Nyquist Frequency
Aliasing
Moiré
Anti-Aliasing Filter
Optical Low-Pass Filter
OLPF
Image Stabilization
Optical Stabilization
Sensor-Shift Stabilization
Rolling Shutter
Global Shutter
Sensor
Image Sensor
CMOS
CCD
Photodiode
Photosite
Pixel
Pixel Pitch
Microlens
Quantum Efficiency
Full Well Capacity
Read Noise
Shot Noise
Photon Noise
Thermal Noise
Dark Current
Signal-to-Noise Ratio
SNR
Analog Gain
Digital Gain
ADC
Analog-to-Digital Converter
Bit Depth
8-bit
10-bit
12-bit
14-bit
16-bit
32-bit
Floating Point
Integer
Linear Data
Gamma-Encoded Data
Quantization
Quantization Error
Banding
Posterization
Saturation Point
Black Level Subtraction
White Level Normalization
Dual Gain
Dual Conversion Gain
Base ISO
Native ISO
ISO Invariance
Readout
Sensor Readout
DNG
RAW Container
Optics
Geometric Optics
Physical Optics
Wave Optics
Ray
Wavefront
Photon
Electromagnetic Radiation
Electromagnetic Spectrum
Visible Light
Infrared
Ultraviolet
Wavelength
Frequency
Amplitude
Phase
Coherence
Interference
Refraction
Reflection
Transmission
Absorption
Scattering
Rayleigh Scattering
Mie Scattering
Polarization
Linear Polarization
Circular Polarization
Birefringence
Refractive Index
Snell's Law
Fresnel Reflection
Fresnel Equations
Total Internal Reflection
Dispersion
Prism
Lens Equation
Magnification
Numerical Aperture
Aperture Stop
Field Stop
Point Spread Function
PSF
Line Spread Function
Optical Transfer Function
OTF
Fourier Transform
Spatial Frequency
Convolution
Kernel
Gaussian Blur
Motion Blur
Depth Blur
Defocus
Defocus Blur
Airy Pattern
Fraunhofer Diffraction
Fresnel Diffraction
Color
Color Science
Colorimetry
Chromaticity Diagram
CIE
CIE 1931
CIE XYZ
XYZ
xyY
CIELAB
Lab
L*a*b*
LCH
CIELUV
Delta E
Delta E 2000
Illuminant
D50
D55
D65
DCP
ICC
ICC Profile
Input Profile
Working Profile
Display Profile
Monitor Profile
Output Profile
Abstract Profile
Color Space
Working Color Space
sRGB
Adobe RGB
ProPhoto RGB
Rec.2020
Rec.2100
Display P3
Apple Display P3
Wide Gamut
Gamut
Gamut Mapping
Out of Gamut
Rendering Intent
Perceptual
Relative Colorimetric
Absolute Colorimetric
Saturation Intent
Color Management
Color Appearance
CIECAM02
CAM16
Jzazbz
JzCzhz
HSV
HSL
RGB
YRGB
YCbCr
Luminance
Luma
Chroma
Hue
Saturation
Lightness
Brightness
Gamma
Transfer Function
Tone Reproduction Curve
TRC
OETF
EOTF
PQ
HLG
Scene-Referred
Display-Referred
Scene Linear
Linear RGB
Gamma Correction
White Balance
Color Temperature
Correlated Color Temperature
CCT
Tint
Planckian Locus
Blackbody Radiation
Metamerism
Metameric Failure
Color Checker
Color Target
IT8 Target
Spectral Sensitivity
Spectral Power Distribution
SPD
Printer Profile
Soft Proofing
Hard Proof
CMYK
Printer Gamut
Paper White
Black Point Compensation
BPC
Dither
Halftone
Dot Gain
DPI
PPI
Pixels Per Inch
Dots Per Inch
Resampling
Interpolation
Lanczos
Bicubic
Bilinear
Nearest Neighbor
JPEG
JPEG XL
PNG
TIFF
WebP
HEIF
AVIF
Lossless Compression
Lossy Compression
Bitrate
Chroma Subsampling
4:4:4
4:2:2
4:2:0
Metadata
EXIF
IPTC
XMP
ExifTool
Sidecar
File Format
File Naming
File Path
Directory
Folder
Catalog
Asset Management
Digital Asset Management
DAM
Backup
Archive
Versioning
Checksum
Hash
MD5
SHA-1
SHA-256
UUID
Timestamp
Time Zone
GPS
Geotagging
Keyword
Rating
Color Label
Tag
Collection
Import
Batch Queue
Cache
Thumbnail Cache
Preview
Preview Image
Embedded Preview
Histogram
Clipping Indicator
Monitor Calibration
Calibration
Profiling
Display Calibration
Colorimeter
Spectrophotometer
Algorithm
Matrix
Vector
Transform
Discrete Fourier Transform
DFT
FFT
Wavelet Transform
Radius
Sigma
Threshold
Mask
Opacity
Blend Mode
Histogram Equalization
Local Histogram Equalization
CLAHE
Gradient
Laplacian
Edge Detection
Bilateral Filter
Guided Filter
Gaussian Filter
Sharpening Kernel
Deconvolution Kernel
Regularization
Iteration
Damping
Regression
Clustering
Principal Component Analysis
PCA
Game Changer
""".strip().splitlines()

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
    rel = re.sub(r"/index\.html$", "", rel)
    rel = re.sub(r"\.html$", "", rel)
    rel = re.sub(r"[^A-Za-z0-9]+", "-", rel)
    rel = rel.strip("-")
    return rel or "page"

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
          <p\b[^>]*>\s*(?:&nbsp;|\u00a0|\s|<br\s*/?>)*</p>
        | <div\b[^>]*>\s*(?:&nbsp;|\u00a0|\s|<br\s*/?>)*</div>
        | <section\b[^>]*>\s*(?:&nbsp;|\u00a0|\s|<br\s*/?>)*</section>
        | <figure\b[^>]*>\s*(?:&nbsp;|\u00a0|\s|<br\s*/?>)*</figure>
        | <span\b[^>]*>\s*(?:&nbsp;|\u00a0|\s|<br\s*/?>)*</span>
        | <a\b[^>]*(?:id|name)=["'][^"']+["'][^>]*>\s*</a>
        | <hr\b[^>]*>
        )
        """,
        re.X,
    )

    while changed:
        before = s
        s = empty_block.sub("", s)
        changed = s != before

    return s

def extract_hugo_frontmatter(text: str) -> str:
    if text.startswith("---\n") or text.startswith("---\r\n"):
        m = re.match(r"(?s)^---\s*\n(.*?)\n---\s*(?:\n|$)", text)
        if m:
            return m.group(1)

    if text.startswith("+++\n") or text.startswith("+++\r\n"):
        m = re.match(r"(?s)^\+\+\+\s*\n(.*?)\n\+\+\+\s*(?:\n|$)", text)
        if m:
            return m.group(1)

    return ""

_content_file_index = None

def content_lookup_key(value: str) -> str:
    value = html.unescape(value or "").strip()
    value = urllib.parse.unquote(value)
    value = value.replace("\\", "/")
    value = re.sub(r"/+", "/", value)

    value = value.split("#", 1)[0]
    value = value.split("?", 1)[0]
    value = value.strip("/")

    value = re.sub(r"/index\.html$", "", value, flags=re.I)
    value = re.sub(r"\.html$", "", value, flags=re.I)
    value = re.sub(r"\.(md|markdown)$", "", value, flags=re.I)

    value = value.replace("_", "-")
    value = re.sub(r"[^A-Za-z0-9/.-]+", "-", value)
    value = re.sub(r"-+", "-", value)
    value = re.sub(r"/+", "/", value)
    value = value.strip("-/")

    return value.lower()

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


def extract_frontmatter_list_field(fm: str, field: str) -> list[str]:
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
    
def build_content_file_index():
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

            try:
                rel = str(p.relative_to(CONTENTS_DIR)).replace("\\", "/")
            except Exception:
                continue

            if not content_rel_is_probably_english(rel):
                continue

            rel_no_ext = re.sub(r"\.[^.]+$", "", rel)

            add(rel, p)
            add(rel_no_ext, p)
            add("/" + rel, p)
            add("/" + rel_no_ext, p)

            if rel_no_ext.endswith("/index"):
                add(rel_no_ext[:-len("/index")], p)
                add("/" + rel_no_ext[:-len("/index")], p)

            try:
                text = read_text(p)
            except Exception:
                text = ""

            fm = extract_hugo_frontmatter(text)

            if fm:
                title = extract_frontmatter_string_field(fm, "title")
                url = extract_frontmatter_string_field(fm, "url")
                slug = extract_frontmatter_string_field(fm, "slug")

                if title:
                    add(title, p)

                if url:
                    add(url, p)

                if slug:
                    add(slug, p)
                    parent = str(Path(rel_no_ext).parent).replace("\\", "/")
                    if parent and parent != ".":
                        add(parent + "/" + slug, p)

                for alias in extract_frontmatter_list_field(fm, "aliases"):
                    add(alias, p)

    return index

def find_content_file_for_article_rel(rel: str) -> Path | None:
    global _content_file_index

    if _content_file_index is None:
        _content_file_index = build_content_file_index()

        if not isinstance(_content_file_index, dict):
            print(f"❌ build_content_file_index() returned bad value: {_content_file_index!r}")
            return None

        print(f"✅ Content source lookup keys: {len(_content_file_index)}")

        if len(_content_file_index) < 20:
            print("❌ Content source lookup index is suspiciously small.")
            print(f"❌ CONTENTS_DIR = {CONTENTS_DIR}")
            print(f"❌ CONTENTS_DIR exists: {CONTENTS_DIR.exists()}")

            if CONTENTS_DIR.exists():
                print("---- first content files ----")
                for p in sorted(CONTENTS_DIR.rglob("*"))[:80]:
                    if p.is_file():
                        print(f"   {p}")

            return None

    route = rel.replace("\\", "/")
    route = re.sub(r"/index\.html$", "", route, flags=re.I)
    route = re.sub(r"\.html$", "", route, flags=re.I)
    route = route.strip("/")

    candidates = [
        rel,
        route,
        "/" + route,
        route + "/",
        route + "/index.html",
        Path(route).name,
        route.replace("-", "_"),
        route.replace("_", "-"),
        Path(route).name.replace("-", "_"),
        Path(route).name.replace("_", "-"),
    ]

    for candidate in candidates:
        key = content_lookup_key(candidate)

        if key and key in _content_file_index:
            return _content_file_index[key]

    # Hard fallback:
    # Scan actual CONTENTS_DIR files and match by normalized route/filename.
    wanted_keys = {
        content_lookup_key(route),
        content_lookup_key(Path(route).name),
        content_lookup_key(route.replace("-", "_")),
        content_lookup_key(route.replace("_", "-")),
        slug_route_key(route),
        slug_route_key(Path(route).name),
    }

    wanted_keys = {k for k in wanted_keys if k}

    if CONTENTS_DIR.exists():
        for root, dirs, files in os.walk(CONTENTS_DIR):
            for name in files:
                p = Path(root) / name

                if p.suffix.lower() not in {".md", ".markdown", ".html"}:
                    continue

                try:
                    content_rel = str(p.relative_to(CONTENTS_DIR)).replace("\\", "/")
                except Exception:
                    continue

                if not content_rel_is_probably_english(content_rel):
                    continue

                content_rel_no_ext = re.sub(r"\.[^.]+$", "", content_rel)

                file_keys = {
                    content_lookup_key(content_rel),
                    content_lookup_key(content_rel_no_ext),
                    content_lookup_key(Path(content_rel_no_ext).name),
                    slug_route_key(content_rel_no_ext),
                    slug_route_key(Path(content_rel_no_ext).name),
                }

                file_keys = {k for k in file_keys if k}

                if wanted_keys & file_keys:
                    return p

    # Last-last resort:
    # Match generated Hugo route stem directly against actual source filename stem.
    wanted_stems = {
        route,
        Path(route).name,
        route.replace("-", "_"),
        route.replace("_", "-"),
        Path(route).name.replace("-", "_"),
        Path(route).name.replace("_", "-"),
    }

    wanted_stem_keys = {
        re.sub(r"[^a-z0-9]+", "", x.lower())
        for x in wanted_stems
        if x
    }

    if CONTENTS_DIR.exists():
        for root, dirs, files in os.walk(CONTENTS_DIR):
            for name in files:
                p = Path(root) / name

                if p.suffix.lower() not in {".md", ".markdown", ".html"}:
                    continue

                try:
                    content_rel = str(p.relative_to(CONTENTS_DIR)).replace("\\", "/")
                except Exception:
                    continue

                if not content_rel_is_probably_english(content_rel):
                    continue

                stem = p.stem

                candidate_stem_keys = {
                    re.sub(r"[^a-z0-9]+", "", stem.lower()),
                    re.sub(r"[^a-z0-9]+", "", stem.replace("-", "_").lower()),
                    re.sub(r"[^a-z0-9]+", "", stem.replace("_", "-").lower()),
                }

                if wanted_stem_keys & candidate_stem_keys:
                    return p

    return None

def extract_aliases_from_content_file(path: Path | None) -> list[str]:
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

            lm = re.match(r"^\s*-\s*(.*?)\s*$", child)
            if lm:
                aliases.append(lm.group(1).strip().strip('"\''))
                i += 1
                continue

            break

    return sorted(set(a for a in aliases if a))
    
def clean_person_name(name: str) -> str:
    name = html.unescape(name or "").strip()
    name = re.sub(r"\s+", " ", name)
    name = name.strip(" \t\r\n,;|[]{}()\"'")

    m = re.search(r"(?i)\bname\s*:\s*['\"]?([^,'\"}]+)", name)
    if m:
        name = m.group(1).strip()

    name = name.strip(" \t\r\n,;|[]{}()\"'")

    blocked = {
        "",
        "rawpedia",
        "rawtherapee",
        "rawtherapee manual",
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

def split_contributor_field(value: str) -> list[str]:
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

def extract_contributors_from_hugo_frontmatter(text: str) -> set[str]:
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

        if rest and rest not in ("|", ">"):
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

            lm = re.match(r"^\s*-\s*(.*?)\s*$", child)
            if lm:
                item = lm.group(1).strip()
                for name in split_contributor_field(item):
                    contributors.add(name)
                i += 1
                continue

            lm = re.match(r"^\s*name\s*:\s*(.*?)\s*$", child, flags=re.I)
            if lm:
                for name in split_contributor_field(lm.group(1)):
                    contributors.add(name)
                i += 1
                continue

            i += 1

    return contributors

def extract_contributors_from_metadata(text: str) -> set[str]:
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

def harvest_contributors_from_contents():
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

    print(f"✅ Hugo source metadata files scanned: {scanned}")
    return found

def read_authors_file():
    if not RT_AUTHORS_TXT.exists():
        return []

    names = []
    text = read_text(RT_AUTHORS_TXT)

    for line in text.splitlines():
        raw = line.strip()

        if not raw:
            continue

        if raw.startswith("#"):
            continue

        if raw.lower().startswith(("rawtherapee", "copyright", "authors", "contributors")):
            continue

        raw = re.sub(r"<[^>]*>", "", raw)
        raw = re.sub(r"\s*[-–—]\s*.*$", "", raw).strip()
        raw = re.sub(r"\s{2,}.*$", "", raw).strip()
        raw = raw.strip(" \t\r\n,;")

        if not raw:
            continue

        if len(raw) > 100:
            continue

        names.append(raw)

    seen = set()
    unique = []

    for name in names:
        key = name.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(name)

    return unique

def read_license_text():
    if RT_LICENSE_TXT and RT_LICENSE_TXT.exists():
        text = read_text(RT_LICENSE_TXT)
        text = text.strip()
        if text:
            return text, str(RT_LICENSE_TXT)

    return (
        "No LICENSE, LICENSE.txt, COPYING, or COPYING.txt file was found in ~/repo-rt.",
        "",
    )

def extract_redirect_target_from_source_text(text: str) -> str:
    """
    Return the redirect target from a RawPedia/Hugo source file.

    Handles:
      #REDIRECT [[Target]]
      #REDIRECT [[Target|label]]
      REDIRECT Target
      meta refresh / canonical HTML
      front matter redirect/url/target-ish fields when present
    """
    raw = text or ""
    fm = extract_hugo_frontmatter(raw)
    # Hugo/RawPedia redirect shortcodes, examples:
    # {{< redirect "Preview_Modes" >}}
    # {{% redirect "Preview_Modes" %}}
    # {{< redirect target="Preview_Modes" >}}
    # {{< redirect url="Preview_Modes" >}}
    m = re.search(
        r'''\{\{[%<]\s*redirect\s+(?:target\s*=\s*|url\s*=\s*|to\s*=\s*)?["']([^"']+)["']\s*[%>]\}\}''',
        raw,
        flags=re.I | re.S,
    )
    if m:
        return m.group(1).strip()
    if fm:
        for field in (
            "redirect",
            "redirect_to",
            "redirectto",
            "target",
            "to",
        ):
            value = extract_frontmatter_string_field(fm, field)
            if value:
                return value.strip()

    # MediaWiki-style redirect.
    m = re.search(
        r"(?im)^\s*#?\s*redirect\s*\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]*)?\]\]",
        raw,
    )
    if m:
        return m.group(1).strip()

    # Plain redirect text.
    plain = html_to_plain_text(raw)
    m = re.search(r"(?i)^\s*#?\s*redirect\s+(.+?)\s*$", plain.strip())
    if m:
        return m.group(1).strip()

    # HTML meta refresh.
    m = re.search(
        r'<meta\b[^>]*http-equiv=["\']?refresh["\']?[^>]*content=["\'][^"\']*url=([^"\';]+)',
        raw,
        flags=re.I | re.S,
    )
    if m:
        return html.unescape(m.group(1)).strip()

    # HTML canonical link.
    m = re.search(
        r'<link\b[^>]*rel=["\']canonical["\'][^>]*href=["\']([^"\']+)["\']',
        raw,
        flags=re.I | re.S,
    )
    if m:
        return html.unescape(m.group(1)).strip()

    m = re.search(
        r'<link\b[^>]*href=["\']([^"\']+)["\'][^>]*rel=["\']canonical["\']',
        raw,
        flags=re.I | re.S,
    )
    if m:
        return html.unescape(m.group(1)).strip()

    return ""


def source_file_is_redirect(path: Path) -> bool:
    try:
        text = read_text(path)
    except Exception:
        return False

    return bool(extract_redirect_target_from_source_text(text))


def find_content_file_for_redirect_target(target: str, current_file: Path | None = None) -> Path | None:
    """
    Resolve a redirect target to an actual source file in CONTENTS_DIR.

    Target may be:
      Some Page
      Some_Page
      /some-page/
      some-page/index.html
      ../Other_Page
    """
    if not target:
        return None

    target = html.unescape(target).strip()
    target = urllib.parse.unquote(target)
    target = target.split("#", 1)[0].split("?", 1)[0].strip()

    if not target:
        return None

    candidates = []

    candidates.append(target)
    candidates.append(target.replace(" ", "_"))
    candidates.append(target.replace(" ", "-"))
    candidates.append("/" + target.strip("/"))
    candidates.append(target.strip("/") + "/")
    candidates.append(target.strip("/") + "/index.html")

    # If redirect is relative to a source directory, try that too.
    if current_file is not None:
        try:
            current_rel_parent = str(current_file.relative_to(CONTENTS_DIR).parent).replace("\\", "/")
            if current_rel_parent and current_rel_parent != ".":
                candidates.append(current_rel_parent + "/" + target.strip("/"))
                candidates.append(current_rel_parent + "/" + target.replace(" ", "_").strip("/"))
                candidates.append(current_rel_parent + "/" + target.replace(" ", "-").strip("/"))
        except Exception:
            pass

    for candidate in candidates:
        found = find_content_file_for_article_rel(candidate)
        if found:
            return found

    return None

# ----------------------------------------------------------------------
# Final authoritative QR source resolver.
#
# This resolver intentionally reads source file names and source file
# contents from Git, not from the macOS working tree.
#
# Reason:
# A normal macOS checkout may not reliably expose two files which differ
# only by case:
#
#   Preview_modes.md   redirect stub
#   Preview_Modes.md   real article
#
# Git can still tell us the exact tree paths and exact blob contents.
# ----------------------------------------------------------------------

_qr_git_content_rel_cache = None
_qr_git_blob_text_cache = {}


def qr_compact_key(value: str) -> str:
    value = html.unescape(value or "").strip()
    value = urllib.parse.unquote(value)
    value = value.replace("\\", "/")
    value = value.split("#", 1)[0].split("?", 1)[0]

    value = re.sub(r"/index\.html$", "", value, flags=re.I)
    value = re.sub(r"\.html$", "", value, flags=re.I)
    value = re.sub(r"\.(md|markdown|html)$", "", value, flags=re.I)

    value = value.strip("/").lower()

    return re.sub(r"[^a-z0-9]+", "", value)


def qr_git_root() -> Path:
    return CONTENTS_DIR.parent


def qr_git_content_rels() -> list[str]:
    global _qr_git_content_rel_cache

    if _qr_git_content_rel_cache is not None:
        return _qr_git_content_rel_cache

    rels = []

    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(qr_git_root()),
                "ls-tree",
                "-r",
                "--name-only",
                "HEAD",
                "content",
            ],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        for line in result.stdout.splitlines():
            line = line.strip().replace("\\", "/")

            if not line.startswith("content/"):
                continue

            rel = line[len("content/"):]

            if Path(rel).suffix.lower() not in {".md", ".markdown", ".html"}:
                continue

            if not content_rel_is_probably_english(rel):
                continue

            rels.append(rel)

    except Exception as e:
        print(f"❌ Could not read RawPedia Git tree for QR sources: {e}")
        print(f"❌ Git root tried: {qr_git_root()}")
        sys.exit(1)

    _qr_git_content_rel_cache = sorted(set(rels))

    if not _qr_git_content_rel_cache:
        print("❌ RawPedia Git tree returned no English content source files.")
        print(f"❌ Git root tried: {qr_git_root()}")
        sys.exit(1)

    return _qr_git_content_rel_cache


def qr_git_blob_text(content_rel: str) -> str:
    content_rel = (content_rel or "").replace("\\", "/").strip("/")

    if not content_rel:
        return ""

    if content_rel in _qr_git_blob_text_cache:
        return _qr_git_blob_text_cache[content_rel]

    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(qr_git_root()),
                "show",
                f"HEAD:content/{content_rel}",
            ],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        text = result.stdout
    except Exception:
        text = ""

    _qr_git_blob_text_cache[content_rel] = text
    return text


def qr_local_path_for_content_rel(content_rel: str) -> Path:
    return CONTENTS_DIR / content_rel


def qr_source_title_for_rel(content_rel: str) -> str:
    text = qr_git_blob_text(content_rel)

    if not text:
        return ""

    fm = extract_hugo_frontmatter(text)

    if not fm:
        return ""

    return extract_frontmatter_string_field(fm, "title")


def qr_redirect_target_for_rel(content_rel: str) -> str:
    text = qr_git_blob_text(content_rel)

    if not text:
        return ""

    target = extract_redirect_target_from_source_text(text)

    if target:
        return target.strip()

    plain = html_to_plain_text(text)

    m = re.search(
        r"(?im)^\s*#?\s*redirect\s*\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]*)?\]\]",
        text,
    )
    if m:
        return m.group(1).strip()

    m = re.search(r"(?im)^\s*#?\s*redirect\s+(.+?)\s*$", plain)
    if m:
        return m.group(1).strip()

    return ""


def qr_rel_is_redirect(content_rel: str) -> bool:
    return bool(qr_redirect_target_for_rel(content_rel))


def qr_source_redirect_target(path: Path) -> str:
    """
    Compatibility wrapper for older audit code.
    Prefer qr_redirect_target_for_rel() for QR work.
    """
    try:
        rel = str(path.resolve().relative_to(CONTENTS_DIR)).replace("\\", "/")
    except Exception:
        rel = path.name

    return qr_redirect_target_for_rel(rel)


def qr_source_is_redirect(path: Path) -> bool:
    """
    Compatibility wrapper for older audit code.
    Prefer qr_rel_is_redirect() for QR work.
    """
    try:
        rel = str(path.resolve().relative_to(CONTENTS_DIR)).replace("\\", "/")
    except Exception:
        rel = path.name

    return qr_rel_is_redirect(rel)


def qr_title_filename_candidates(title: str) -> list[str]:
    title = html.unescape(title or "").strip()
    title = re.sub(r"^\s*RawPedia\s*-\s*", "", title, flags=re.I).strip()

    if not title:
        return []

    cleaned = title.replace("&", "and")
    cleaned = re.sub(r"[/:;,.!?()\[\]{}\"'“”‘’]+", " ", cleaned)
    cleaned = re.sub(r"\s+", "_", cleaned.strip())
    cleaned = re.sub(r"_+", "_", cleaned).strip("_")

    if not cleaned:
        return []

    parts = [p for p in cleaned.split("_") if p]

    title_cased = "_".join(part[:1].upper() + part[1:] for part in parts)

    smart_parts = []

    for part in parts:
        if part.isupper():
            smart_parts.append(part)
        elif re.fullmatch(r"[A-Z0-9]{2,}", part):
            smart_parts.append(part)
        else:
            smart_parts.append(part[:1].upper() + part[1:])

    smart_title_cased = "_".join(smart_parts)

    candidates = []

    for stem in (smart_title_cased, title_cased, cleaned):
        if not stem:
            continue

        candidates.append(stem + ".md")
        candidates.append(stem + ".markdown")
        candidates.append(stem + ".html")

    out = []
    seen = set()

    for item in candidates:
        if item not in seen:
            seen.add(item)
            out.append(item)

    return out


def qr_file_keys_for_rel(content_rel: str) -> set[str]:
    rel_no_ext = re.sub(r"\.[^.]+$", "", content_rel)
    stem = Path(rel_no_ext).name
    title = qr_source_title_for_rel(content_rel)

    keys = {
        qr_compact_key(content_rel),
        qr_compact_key(rel_no_ext),
        qr_compact_key(stem),
        qr_compact_key(stem.replace("_", " ")),
        qr_compact_key(stem.replace("-", " ")),
    }

    if title:
        keys.add(qr_compact_key(title))
        keys.add(qr_compact_key(title.replace(" ", "_")))
        keys.add(qr_compact_key(title.replace(" ", "-")))

    return {k for k in keys if k}


def qr_target_keys(target: str) -> set[str]:
    target = html.unescape(target or "").strip()
    target = urllib.parse.unquote(target)
    target = target.split("#", 1)[0].split("?", 1)[0].strip()

    variants = {
        target,
        target.replace(" ", "_"),
        target.replace(" ", "-"),
        target.replace("_", " "),
        target.replace("-", " "),
        "/" + target.strip("/"),
        target.strip("/") + "/index.html",
        target.strip("/") + ".md",
        Path(target).name,
    }

    return {qr_compact_key(v) for v in variants if qr_compact_key(v)}


def qr_wanted_keys(title: str, rel: str) -> set[str]:
    route = rel.replace("\\", "/")
    route = re.sub(r"/index\.html$", "", route, flags=re.I)
    route = re.sub(r"\.html$", "", route, flags=re.I)
    route = route.strip("/")

    keys = {
        qr_compact_key(title),
        qr_compact_key(route),
        qr_compact_key(Path(route).name),
        qr_compact_key(route.replace("-", "_")),
        qr_compact_key(route.replace("_", "-")),
        qr_compact_key(Path(route).name.replace("-", "_")),
        qr_compact_key(Path(route).name.replace("_", "-")),
    }

    for name in qr_title_filename_candidates(title):
        keys.add(qr_compact_key(Path(name).stem))

    return {k for k in keys if k}


def qr_case_score(content_rel: str, title: str = "") -> float:
    stem = Path(re.sub(r"\.[^.]+$", "", content_rel)).name
    parts = [p for p in re.split(r"[_\-\s]+", stem) if p]

    score = 0.0

    if qr_rel_is_redirect(content_rel):
        score -= 100000000
    else:
        score += 100000000

    score += sum(1 for p in parts if p[:1].isupper()) * 10000
    score -= sum(1 for p in parts if p[:1].islower()) * 12000
    score += sum(1 for ch in stem if ch.isupper()) * 100

    if title:
        title_clean = html.unescape(title or "").strip()
        title_clean = re.sub(r"^\s*RawPedia\s*-\s*", "", title_clean, flags=re.I).strip()
        title_clean = title_clean.replace("&", "and")
        title_clean = re.sub(r"[/:;,.!?()\[\]{}\"'“”‘’]+", " ", title_clean)
        title_clean = re.sub(r"\s+", "_", title_clean.strip())
        title_clean = re.sub(r"_+", "_", title_clean).strip("_")

        title_cased = "_".join(
            part[:1].upper() + part[1:]
            for part in title_clean.split("_")
            if part
        )

        if stem == title_cased:
            score += 1000000

    score -= content_rel.count("/") * 100
    score -= len(content_rel) * 0.01

    return score


def qr_best_nonredirect_for_keys(keys: set[str], title: str = "") -> str:
    candidates = []

    for content_rel in qr_git_content_rels():
        if keys & qr_file_keys_for_rel(content_rel):
            candidates.append(content_rel)

    candidates = sorted(set(candidates))

    if not candidates:
        return ""

    nonredirects = [rel for rel in candidates if not qr_rel_is_redirect(rel)]

    if nonredirects:
        nonredirects.sort(key=lambda rel: (-qr_case_score(rel, title), rel))
        return nonredirects[0]

    candidates.sort(key=lambda rel: (-qr_case_score(rel, title), rel))
    return candidates[0]


def qr_find_exact_title_source_rel(title: str) -> str:
    wanted_filenames = qr_title_filename_candidates(title)

    if not wanted_filenames:
        return ""

    wanted_name_keys = {
        qr_compact_key(Path(name).stem)
        for name in wanted_filenames
        if name
    }
    wanted_name_keys = {k for k in wanted_name_keys if k}

    matches = []

    for rel in qr_git_content_rels():
        name = Path(rel).name
        stem_key = qr_compact_key(Path(name).stem)

        if stem_key not in wanted_name_keys:
            continue

        redirect = qr_rel_is_redirect(rel)
        score = qr_case_score(rel, title)

        if name in wanted_filenames:
            score += 5000

        matches.append((score, rel, redirect))

    if not matches:
        return ""

    matches.sort(key=lambda item: (-item[0], item[1]))

    non_redirect_matches = [
        (score, rel, redirect)
        for score, rel, redirect in matches
        if not redirect
    ]

    if non_redirect_matches:
        chosen = non_redirect_matches[0][1]
    else:
        chosen = matches[0][1]

    if qr_rel_is_redirect(chosen):
        print()
        print("❌ QR exact-title resolver found only REDIRECT files:")
        print(f"   title:  {title}")
        print(f"   chosen: content/{chosen}")
        print(f"   target: {qr_redirect_target_for_rel(chosen)}")
        print()
        print("Matching candidates:")
        for score, rel, redirect in matches[:20]:
            marker = "REDIRECT" if redirect else "ARTICLE"
            print(f"   {marker:8} {score:12.2f} content/{rel}")
        print()
        print("First 2000 chars of chosen source:")
        print(qr_git_blob_text(chosen)[:2000])
        sys.exit(1)

    return chosen


def choose_qr_content_rel(title: str, rel: str) -> str:
    hard_redirect_targets = {
        "previewmodes": "Preview_Modes.md",
    }

    title_key = qr_compact_key(title)

    if title_key in hard_redirect_targets:
        forced_rel = hard_redirect_targets[title_key]

        if forced_rel in qr_git_content_rels():
            if qr_rel_is_redirect(forced_rel):
                print()
                print("❌ Hard-forced QR target is unexpectedly a redirect:")
                print(f"   title:  {title}")
                print(f"   source: content/{forced_rel}")
                print(f"   target: {qr_redirect_target_for_rel(forced_rel)}")
                sys.exit(1)

            return forced_rel

    exact_title_rel = qr_find_exact_title_source_rel(title)

    if exact_title_rel and not qr_rel_is_redirect(exact_title_rel):
        return exact_title_rel

    wanted = qr_wanted_keys(title, rel)

    if not wanted:
        return ""

    chosen = qr_best_nonredirect_for_keys(wanted, title)

    if not chosen:
        return ""

    target = qr_redirect_target_for_rel(chosen)

    if target:
        repaired = qr_best_nonredirect_for_keys(qr_target_keys(target), target)

        if repaired and not qr_rel_is_redirect(repaired):
            print(f"↪ QR redirect repaired: {chosen} -> {repaired}")
            return repaired

    return chosen


def github_url_for_article(title: str, rel: str) -> str:
    content_rel = choose_qr_content_rel(title, rel)

    if content_rel:
        if qr_rel_is_redirect(content_rel):
            print()
            print("❌ QR resolver selected a Git redirect source file:")
            print(f"   title:  {title}")
            print(f"   rel:    {rel}")
            print(f"   source: content/{content_rel}")
            print(f"   target: {qr_redirect_target_for_rel(content_rel)}")
            print()
            print("First 2000 chars of chosen source:")
            print(qr_git_blob_text(content_rel)[:2000])
            sys.exit(1)

        return (
            "https://github.com/RawTherapee/RawPedia/blob/master/content/"
            + urllib.parse.quote(content_rel, safe="/")
        )

    route = rel.replace("\\", "/")
    route = re.sub(r"/index\.html$", "", route, flags=re.I)
    route = re.sub(r"\.html$", "", route, flags=re.I)
    route = route.strip("/")

    print(f"⚠️ Could not find actual-cased non-redirect source file for generated page: {rel}")
    print(f"⚠️ QR GitHub URL will use fallback route casing: {route}.md")

    fallback_rel = f"{route}.md" if route else "_index.md"

    return (
        "https://github.com/RawTherapee/RawPedia/blob/master/content/"
        + urllib.parse.quote(fallback_rel, safe="/")
    )
    
def make_article_qr(page_id: str, github_url: str) -> str:
    qr_dir = OUTPUT_HTML.parent / "article-qrs"
    qr_dir.mkdir(parents=True, exist_ok=True)

    qr_path = qr_dir / f"{page_id}.svg"

    try:
        if qr_path.exists():
            qr_path.unlink()

        subprocess.run(
            [
                "qrencode",
                "-t", "SVG",
                "-o", str(qr_path),
                "-m", "1",
                "-s", "5",
                github_url,
            ],
            check=True,
        )
    except FileNotFoundError:
        print("❌ qrencode was not found while generating article QR codes.")
        print("❌ Install it with:")
        print("   brew install qrencode")
        raise
    except subprocess.CalledProcessError as e:
        print("❌ qrencode failed while generating article QR code.")
        print(f"❌ page_id: {page_id}")
        print(f"❌ url: {github_url}")
        print(f"❌ exit status: {e.returncode}")
        raise

    return qr_path.resolve().as_uri()
    
def license_text_to_html_paragraphs(text: str) -> str:
    text = text.strip()

    # Normalize line endings.
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    # Split on blank lines.
    blocks = re.split(r"\n\s*\n+", text)

    out = []

    for block in blocks:
        block = block.strip()

        if not block:
            continue

        # Preserve short all-caps-ish license headings as heading-like divs.
        if (
            len(block) <= 80
            and "\n" not in block
            and re.search(r"[A-Z]", block)
            and block.upper() == block
        ):
            out.append(f'<div class="license-heading">{html.escape(block)}</div>')
            continue

        # Reflow single paragraph lines into one justified paragraph.
        block = re.sub(r"\s*\n\s*", " ", block)
        block = re.sub(r"\s+", " ", block).strip()

        out.append(f"<p>{html.escape(block)}</p>")

    return "\n".join(out)

def title_from_doc(text: str, fallback: str) -> str:
    m = re.search(r"<title[^>]*>(.*?)</title>", text, flags=re.I | re.S)
    if not m:
        return fallback

    title = re.sub(r"<[^>]+>", "", m.group(1))
    title = html.unescape(title).strip()
    title = re.sub(r"^\s*RawPedia\s*-\s*", "", title, flags=re.I)
    title = title.strip()

    return title or fallback

def extract_main_or_body(text: str) -> str:
    m = re.search(r"<main\b[^>]*>(.*?)</main>", text, flags=re.I | re.S)
    if m:
        return m.group(1)

    m = re.search(r"<article\b[^>]*>(.*?)</article>", text, flags=re.I | re.S)
    if m:
        return m.group(1)

    m = re.search(r"<body\b[^>]*>(.*?)</body>", text, flags=re.I | re.S)
    if m:
        return m.group(1)

    return text

def strip_bad_parts(s: str) -> str:
    s = re.sub(r"<script\b.*?</script>", "", s, flags=re.I | re.S)
    s = re.sub(r"<noscript\b.*?</noscript>", "", s, flags=re.I | re.S)
    s = re.sub(r"<style\b.*?</style>", "", s, flags=re.I | re.S)
    s = re.sub(r"<header\b.*?</header>", "", s, flags=re.I | re.S)
    s = re.sub(r"<footer\b.*?</footer>", "", s, flags=re.I | re.S)
    s = re.sub(r"<nav\b.*?</nav>", "", s, flags=re.I | re.S)

    s = re.sub(
        r"<details\b[^>]*>\s*<summary\b[^>]*>\s*Table of Contents\s*</summary>.*?</details>",
        "",
        s,
        flags=re.I | re.S,
    )

    s = re.sub(
        r"<button\b[^>]*>\s*Table of Contents\s*</button>",
        "",
        s,
        flags=re.I | re.S,
    )

    s = re.sub(
        r"<div\b[^>]*(?:id|class)=[\"'][^\"']*(?:toc|TableOfContents|breadcrumbs?|menu|nav)[^\"']*[\"'][^>]*>.*?</div>",
        "",
        s,
        flags=re.I | re.S,
    )

    s = re.sub(r"\sstyle=(['\"]).*?\1", "", s, flags=re.I | re.S)
    s = s.replace("\x0b", "").replace("\x0c", "")

    return strip_empty_leading_blocks(s)

def remove_leading_noise(plain: str, title: str) -> str:
    s = re.sub(r"\s+", " ", plain).strip()

    title_clean = html.unescape(title or "").strip()
    title_clean = re.sub(r"^\s*RawPedia\s*-\s*", "", title_clean, flags=re.I).strip()

    noise_patterns = [
        r"^RawPedia\s*[-–—:]\s*",
        r"^Jump to navigation\s+Jump to search\s+",
        r"^Navigation\s+",
        r"^Contents\s+",
    ]

    changed = True
    while changed:
        changed = False

        before = s
        for pat in noise_patterns:
            s = re.sub(pat, "", s, flags=re.I).strip()

        if title_clean:
            escaped = re.escape(title_clean)
            s = re.sub(rf"^{escaped}\s+", "", s, flags=re.I).strip()
            s = re.sub(rf"^{escaped}$", "", s, flags=re.I).strip()

        if s != before:
            changed = True

    return re.sub(r"\s+", " ", s).strip()

def is_redirect_page_text(raw_text: str, title: str = "") -> bool:
    if re.search(r'<meta[^>]+http-equiv=["\']?refresh["\']?', raw_text, flags=re.I):
        return True

    main = extract_main_or_body(raw_text)
    cleaned = strip_bad_parts(main)
    plain = html_to_plain_text(cleaned)

    if not plain:
        return False

    candidate = remove_leading_noise(plain, title)
    candidate = re.sub(r"^\s*#\s*", "#", candidate).strip()

    upper = candidate.upper()

    if upper == "REDIRECT":
        return True

    if re.match(r"(?i)^#?\s*REDIRECT\b", candidate):
        return True

    idx = upper.find("REDIRECT")
    if idx >= 0:
        before = candidate[:idx].strip()
        after = candidate[idx:].strip()

        before_weak = len(before) <= 260
        after_redirect_like = re.match(r"(?i)^REDIRECT\b", after) is not None

        if before_weak and after_redirect_like:
            return True

        first_700 = candidate[:700]
        if re.search(r"(?i)\bREDIRECT\b", first_700) and len(before) <= 260:
            return True

    return False

def is_main_page_variant(title: str, rel: str) -> bool:
    title_key = html.unescape(title).strip().lower()
    rel_key = rel.lower()

    if title_key.startswith("main page"):
        return True

    if re.search(r"(^|[/_.-])main[-_]?page([/_.-]|$)", rel_key):
        return True

    return False

def is_allowed_english_main_page(title: str, rel: str) -> bool:
    title_key = html.unescape(title).strip().lower()
    rel_key = rel.lower()

    if title_key != "main page":
        return False

    if re.search(r"(^|[/_.-])(fr|es|it|jp|ja|pt|de|ca|ct|zh|cn|ru|nl|pl|tr)([/_.-]|$)", rel_key):
        return False

    canonical_patterns = [
        r"(?i)^main[-_ ]page$",
        r"(?i)^main[-_ ]page/index\.html$",
        r"(?i)^main_page\.html$",
        r"(?i)^main-page\.html$",
    ]

    if any(re.fullmatch(pat, rel_key) for pat in canonical_patterns):
        return True

    if re.search(r"main[-_ ]?page", rel_key, flags=re.I):
        return True

    return False

def should_suppress_page(title: str, rel: str, full_text: str) -> tuple[bool, str]:
    title_key = html.unescape(title).strip().lower()
    rel_key = rel.lower()

    if is_redirect_page_text(full_text, title):
        return True, "redirect"

    if is_main_page_variant(title, rel) and not is_allowed_english_main_page(title, rel):
        return True, "main-page-variant"

    suppressed_exact = {
        "coding rawpedia pages",
        "coding rawpedia",
        "changes",
        "irc",
        "rawpedia book",
        "wavelet new",
        "wavelets new",
        "wavelet new page",
        "waveletnew",
        "how to play raw",
        "translating rawpedia",
        "translating rawpedia article",
    }

    if title_key in suppressed_exact:
        return True, "exact-title"

    suppressed_rel_needles = [
        "coding-rawpedia",
        "coding_rawpedia",
        "/changes/",
        "changes.html",
        "/irc/",
        "irc.html",
        "rawpedia-book",
        "rawpedia_book",
        "wavelet-new",
        "wavelet_new",
        "wavelets-new",
        "wavelets_new",
        "waveletnew",
        "how-to-play-raw",
        "how_to_play_raw",
        "howtoplayraw",
        "translating-rawpedia",
        "translating_rawpedia",
        "/translating/",
        "translating.html",
    ]

    if any(needle in rel_key for needle in suppressed_rel_needles):
        return True, "path"

    return False, ""

def is_probably_english_page(path: Path, title: str, text: str) -> bool:
    rel = rel_from_source(path)
    rel_lower = rel.lower()
    parts = rel_lower.split("/")

    if parts and parts[0] in language_codes:
        return False

    route = re.sub(r"/index\.html$", "", rel_lower)
    route = re.sub(r"\.html$", "", route)
    slug = route.split("/")[-1]

    if re.search(r"(^|[-_])(fr|es|it|jp|ja|pt|de|ca|ct|zh|cn|ru|nl|pl|tr)$", slug):
        return False

    title_clean = html.unescape(title).strip()
    title_lower = title_clean.lower()

    if re.search(r"\s+(fr|es|it|jp|ja|pt|de|ca|ct|zh|cn|ru|nl|pl|tr)$", title_lower):
        return False

    m = re.search(r"<html[^>]*\blang=[\"']([^\"']+)[\"']", text, flags=re.I)
    if m:
        lang = m.group(1).lower()
        if not lang.startswith("en"):
            return False

    translated_title_words = [
        "premier pas", "profondeur", "options en ligne", "éditer",
        "généralités", "utilisation", "dépendances", "compilation",
        "réglages", "ajouter", "le plugin", "mode opératoire",
        "prise en charge", "nitidezza", "riduzione", "profili di",
        "creare profili", "bordi e", "descargar", "opciones",
        "procesamiento", "preferencias", "añadir", "soporte",
        "profundidad", "contribuir", "compilando", "descàrrega", "baixar",
    ]

    if any(word in title_lower for word in translated_title_words):
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

def clean_links(s: str) -> str:
    s = re.sub(r'href=(["\"])#ZgotmplZ\1', 'href="#"', s, flags=re.I)
    return s

def page_kind(title: str, rel: str) -> tuple[int, str]:
    t = title.lower()
    r = rel.lower()
    key = t + " " + r

    sections = [
        (
            "Part I — Getting Started",
            [
                "main page", "getting started", "download", "nightly",
                "install", "windows", "linux", "macos", "wayland",
                "file paths", "portable", "supported cameras", "features",
            ],
        ),
        (
            "Part II — Interface and Workflow",
            [
                "editor", "file browser", "queue", "batch", "favorites",
                "exif", "iptc", "metadata", "keyboard shortcuts", "shortcut",
                "preferences", "preview modes", "saving", "external editor",
                "sidecar", "processing profile", "dynamic processing",
                "profile chooser", "metadata copy",
            ],
        ),
        (
            "Part III — Raw Development Basics",
            [
                "demosaic", "demosaicing", "raw black", "raw white",
                "preprocessing", "dark frame", "dark-frame", "flat field",
                "flat-field", "white balance", "exposure", "black points",
                "white points", "clipping", "floating point",
                "toolchain pipeline", "bit depth", "8-bit", "16-bit",
            ],
        ),
        (
            "Part IV — Tone, Contrast, and Exposure Tools",
            [
                "tone", "exposure", "shadows", "highlights", "dynamic range",
                "contrast", "tone mapping", "retinex", "haze",
                "graduated filter", "soft light", "vibrance", "rgb curves",
                "lab adjustments", "black-and-white", "black and white",
                "channel mixer", "edges", "microcontrast",
            ],
        ),
        (
            "Part V — Color Management and Color Tools",
            [
                "color management", "color appearance", "ciecam", "cam16",
                "jzcz", "jzazbz", "hsv", "rgb and lab", "gamut", "icc",
                "dcp", "input profile", "film simulation", "film emulation",
                "film negative", "color toning", "chromaticity", "profile creator",
            ],
        ),
        (
            "Part VI — Detail, Noise, and Sharpening",
            [
                "sharpen", "capture sharpening", "noise", "denoise", "impulse",
                "defringe", "chromatic aberration", "deconvolution", "detail",
                "wavelet levels", "wavelets",
                "comparison of the 3 rawtherapee noise reduction tools",
            ],
        ),
        (
            "Part VII — Geometry, Lens, and Output",
            [
                "crop", "resize", "lens", "geometry", "perspective",
                "vignetting", "watermark", "framing", "image file formats",
                "compression", "output", "gimp plugin",
            ],
        ),
        (
            "Part VIII — Local Adjustments and Selective Editing",
            [
                "local adjustments", "local contrast", "local controls",
                "local lab", "selective editing", "spot removal", "mask", "red eye",
            ],
        ),
        (
            "Part IX — Advanced Topics, Reference, and Contributing",
            [
                "command-line", "camconst", "new raw formats", "contributing",
                "compiling", "release", "translating", "bug reports", "coverity",
                "rawtherapee processing challenge", "play raw", "troubleshooting",
                "performance", "sounds tab", "tool description", "general comments",
                "general photography", "interact", "localization",
                "game changer", "game-changing",
            ],
        ),
    ]

    for idx, (section, needles) in enumerate(sections):
        if any(n in key for n in needles):
            return idx, section

    return len(sections), "Part X — Remaining Reference Pages"

def page_sort_key(info):
    order, section = page_kind(info["title"], info["rel"])
    title = info["title"].lower()

    priority = 50

    intro_words = [
        "getting started", "features", "download", "preferences",
        "editor", "file browser", "white balance", "exposure",
        "color management", "sharpening", "crop", "local adjustments",
    ]

    for i, w in enumerate(intro_words):
        if title == w or title.startswith(w):
            priority = i
            break

    return (order, priority, title, info["rel"].lower())

def resolve_local_asset(src: str, page_path: Path) -> Path | None:
    raw = html.unescape(src).strip()

    if not raw or raw.startswith(("http://", "https://", "data:", "mailto:", "#")):
        return None

    parsed = urllib.parse.urlsplit(raw)
    path_part = urllib.parse.unquote(parsed.path)

    candidates = []

    if path_part.startswith("/"):
        candidates.append(SOURCE_DIR / path_part.lstrip("/"))
    else:
        candidates.append(page_path.parent / path_part)
        candidates.append(SOURCE_DIR / path_part)

    for c in candidates:
        try:
            c = c.resolve()
        except FileNotFoundError:
            pass

        if c.exists() and c.suffix.lower() in asset_exts:
            return c

    base = Path(path_part).name.lower()
    found = asset_by_name.get(base)
    if found and found.exists():
        return found

    return None

def rewrite_images(s: str, page_path: Path, page_title: str, page_rel: str) -> str:
    def repl(m):
        tag = m.group(0)
        src = m.group(3)
        found = resolve_local_asset(src, page_path)

        if found:
            safe_uri = html.escape(found.resolve().as_uri(), quote=True)
            tag = re.sub(
                r'\bsrc=(["\']).*?\1',
                f'src="{safe_uri}"',
                tag,
                count=1,
                flags=re.I | re.S,
            )
            return tag

        raw = html.unescape(src.strip())
        filename = Path(urllib.parse.urlsplit(raw).path).name or raw or "unknown image"

        missing_images.append({
            "image": raw,
            "filename": filename,
            "page_title": page_title,
            "page_rel": page_rel,
        })

        return (
            '<div class="missing-image">'
            '<strong>Missing image</strong>'
            f'<div class="missing-file">{html.escape(filename)}</div>'
            f'<div class="missing-path">{html.escape(raw)}</div>'
            '</div>'
        )

    return re.sub(
        r'(<img\b[^>]*?\bsrc=)(["\'])(.*?)(\2[^>]*>)',
        repl,
        s,
        flags=re.I | re.S,
    )

def prefix_ids_and_anchors(s: str, prefix: str) -> str:
    def id_repl(m):
        attr = m.group(1)
        quote = m.group(2)
        value = m.group(3)

        if value.startswith(prefix + "-"):
            return m.group(0)

        return f'{attr}={quote}{prefix}-{value}{quote}'

    s = re.sub(r'\b(id|name)=(["\'])([^"\']+)\2', id_repl, s, flags=re.I)

    def href_repl(m):
        quote = m.group(1)
        frag = m.group(2)

        if frag.startswith(prefix + "-"):
            return m.group(0)

        return f'href={quote}#{prefix}-{frag}{quote}'

    s = re.sub(r'href=(["\"])#([^"\']+)\1', href_repl, s, flags=re.I)

    return s
    
def normalize_manual_link_key(path: str) -> str:
    path = html.unescape(path or "").strip()
    path = urllib.parse.unquote(path)
    path = path.replace("\\", "/")
    path = re.sub(r"/+", "/", path)
    path = path.strip()

    if not path:
        return ""

    # Remove query and fragment before matching the page path.
    path = path.split("#", 1)[0]
    path = path.split("?", 1)[0]

    path = path.strip("/")

    if path.endswith("/index.html"):
        path = path[:-len("/index.html")]
    elif path == "index.html":
        path = ""
    elif path.endswith(".html"):
        path = path[:-len(".html")]

    path = path.strip("/").lower()

    return path

def slug_route_key(value: str) -> str:
    value = html.unescape(value or "").strip()
    value = urllib.parse.unquote(value)
    value = value.replace("\\", "/")
    value = re.sub(r"/+", "/", value)
    value = value.strip()

    value = value.split("#", 1)[0]
    value = value.split("?", 1)[0]
    value = value.strip("/")

    value = re.sub(r"/index\.html$", "", value, flags=re.I)
    value = re.sub(r"\.html$", "", value, flags=re.I)

    value = value.strip("/").lower()

    # Make old RawPedia/wiki-ish routes match Hugo routes.
    value = value.replace("_", "-")
    value = re.sub(r"[^a-z0-9/.-]+", "-", value)
    value = re.sub(r"-+", "-", value)
    value = re.sub(r"/+", "/", value)
    value = value.strip("-/")

    return value


def title_route_key(title: str) -> str:
    title = html.unescape(title or "").strip().lower()
    title = title.replace("&", "and")
    title = re.sub(r"[^a-z0-9]+", "-", title)
    title = re.sub(r"-+", "-", title).strip("-")
    return title

def add_rawpedia_legacy_aliases(link_map):
    """
    Old RawPedia/Hugo routes which do not match current generated page slugs.
    Only add aliases whose target page actually exists in this manual.
    """

    aliases = {
        "the-image-editor-tab": "editor",
        "the_image_editor_tab": "editor",

        "the-file-browser-tab": "file-browser-tab",
        "the_file_browser_tab": "file-browser-tab",

        "the-batch-queue": "queue",
        "the_batch_queue": "queue",

        "saving": "saving-images",
        "saving-images": "saving-images",

        "lens/geometry": "lens-geometry",
        "lens-geometry": "lens-geometry",

        "batch-adjustments-sync": "batch-adjustments-sync",
        "batch_adjustments_-_sync": "batch-adjustments-sync",

        "sidecar-files-processing-profiles": "sidecar-files-processing-profiles",
        "sidecar_files_-_processing_profiles": "sidecar-files-processing-profiles",

        "flat-field": "flat-field",
        "flat_field": "flat-field",

        "dark-frame": "dark-frame",
        "dark_frame": "dark-frame",

        "auto-matched-curve": "rgb-curves",
        "auto_matched_curve": "rgb-curves",
    }

    existing_targets = set(link_map.values())

    for old_route, page_id in aliases.items():
        target = f"#page-{page_id}"

        # Do not create dead internal links.
        if target not in existing_targets:
            continue

        link_map.setdefault(slug_route_key(old_route), target)
        link_map.setdefault(slug_route_key("/" + old_route + "/"), target)

    return link_map

def build_manual_link_map(infos):
    link_map = {}

    for info in infos:
        href = f"#page-{info['id']}"

        rel = info["rel"].replace("\\", "/")
        route = rel
        route = re.sub(r"/index\.html$", "", route, flags=re.I)
        route = re.sub(r"\.html$", "", route, flags=re.I)
        route = route.strip("/")

        keys = {
            slug_route_key(rel),
            slug_route_key("/" + rel),
            slug_route_key(route),
            slug_route_key("/" + route),
            slug_route_key(route + "/"),
            slug_route_key(route + "/index.html"),
            slug_route_key(info["id"]),
            title_route_key(info["title"]),
            slug_route_key(title_route_key(info["title"])),
        }

        # Old/common RawPedia short-name aliases by title.
        tkey = title_route_key(info["title"])
        keys.add(tkey.replace("-", "_"))
        keys.add(tkey.replace("-", " "))

        # Explicit aliases harvested from Hugo front matter.
        for alias in info.get("aliases", []):
            keys.add(slug_route_key(alias))

        for key in keys:
            key = slug_route_key(key)
            if key:
                link_map.setdefault(key, href)

    return add_rawpedia_legacy_aliases(link_map)

def is_rawpedia_host(netloc: str) -> bool:
    host = (netloc or "").lower()

    # Old and current RawPedia hosts.
    return host in {
        "rawpedia.rawtherapee.com",
        "www.rawpedia.rawtherapee.com",
        "rawpedia.pixls.us",
        "www.rawpedia.pixls.us",
        "rawpedia.rawpixls.us",
        "www.rawpedia.rawpixls.us",
    }

def rewrite_one_manual_href(href: str, page_path: Path, manual_link_map: dict[str, str]) -> str:
    raw = html.unescape(href or "").strip()

    if not raw:
        return href

    if raw.startswith(("#", "mailto:", "tel:", "data:", "javascript:")):
        return raw

    parsed = urllib.parse.urlsplit(raw)

    asset_or_download_exts = asset_exts | {
        ".pdf", ".zip", ".7z", ".gz", ".bz2", ".xz",
        ".pp3", ".dcp", ".icc", ".icm", ".txt", ".json",
        ".exe", ".dmg", ".appimage"
    }

    path_ext = Path(urllib.parse.unquote(parsed.path)).suffix.lower()

    if path_ext in asset_or_download_exts:
        if parsed.scheme in {"http", "https"} and is_rawpedia_host(parsed.netloc):
            return urllib.parse.urlunsplit((
                "https",
                urllib.parse.urlsplit(RAWPEDIA_ONLINE_URL).netloc,
                parsed.path,
                parsed.query,
                parsed.fragment,
            ))

        return raw

    def with_fragment(target: str, fragment: str) -> str:
        if not fragment:
            return target

        # For now, land on the article page. This is safer than inventing
        # cross-page heading anchors which may or may not exist.
        return target

    def online_rawpedia_url(path: str, query: str = "", fragment: str = "") -> str:
        fixed = urllib.parse.urlunsplit((
            "https",
            urllib.parse.urlsplit(RAWPEDIA_ONLINE_URL).netloc,
            path or "/",
            query,
            fragment,
        ))
        return fixed

    # Protocol-relative URL, including //localhost:1313/fr/foo/
    if raw.startswith("//"):
        fake = urllib.parse.urlsplit("https:" + raw)
        key = slug_route_key(fake.path)

        if key in manual_link_map:
            return with_fragment(manual_link_map[key], fake.fragment)

        # Do not leave //localhost... in the PDF. Make it a real web URL.
        return online_rawpedia_url(fake.path, fake.query, fake.fragment)

    # RawPedia web URL.
    if parsed.scheme in {"http", "https"}:
        host = (parsed.netloc or "").lower()

        if not is_rawpedia_host(host) and not host.startswith("localhost"):
            return raw

        key = slug_route_key(parsed.path)

        if key in manual_link_map:
            return with_fragment(manual_link_map[key], parsed.fragment)

        return online_rawpedia_url(parsed.path, parsed.query, parsed.fragment)

    # file:///foo/ produced by old cleanup/base-url behavior.
    if parsed.scheme == "file":
        key = slug_route_key(parsed.path)

        if key in manual_link_map:
            return with_fragment(manual_link_map[key], parsed.fragment)

        # Do not leave broken pseudo-file article links.
        if not Path(urllib.parse.unquote(parsed.path)).exists():
            return online_rawpedia_url(parsed.path, parsed.query, parsed.fragment)

        return raw

    # Root-relative link, e.g. /saving/
    if raw.startswith("/"):
        key = slug_route_key(parsed.path)

        if key in manual_link_map:
            return with_fragment(manual_link_map[key], parsed.fragment)

        return online_rawpedia_url(parsed.path, parsed.query, parsed.fragment)

    # Relative link, e.g. lens/geometry#distortion_correction
    rel_path = urllib.parse.unquote(parsed.path)
    key = slug_route_key(rel_path)

    if key in manual_link_map:
        return with_fragment(manual_link_map[key], parsed.fragment)

    try:
        resolved = (page_path.parent / rel_path).resolve()
        rel_to_source = str(resolved.relative_to(SOURCE_DIR)).replace("\\", "/")
        key = slug_route_key(rel_to_source)

        if key in manual_link_map:
            return with_fragment(manual_link_map[key], parsed.fragment)
    except Exception:
        pass

    # Last resort: do not leave PDF-hostile relative links.
    if parsed.path:
        return online_rawpedia_url("/" + parsed.path.lstrip("/"), parsed.query, parsed.fragment)

    return raw


def rewrite_article_links_to_manual(content: str, page_path: Path, manual_link_map: dict[str, str]) -> str:
    def href_repl(m):
        quote = m.group(1)
        href = m.group(2)

        new_href = rewrite_one_manual_href(href, page_path, manual_link_map)

        return f'href={quote}{html.escape(new_href, quote=True)}{quote}'

    content = re.sub(
        r'\bhref=(["\'])(.*?)\1',
        href_repl,
        content,
        flags=re.I | re.S,
    )

    return content
    
def normalize_internal_href_fragments(content: str) -> str:
    def href_repl(m):
        quote = m.group(1)
        href = html.unescape(m.group(2)).strip()

        if not href.startswith("#"):
            return m.group(0)

        if href in {"#", "#ZgotmplZ"}:
            return f'href={quote}#{quote}'

        frag = href[1:]

        # Decode percent-encoded anchors like %ce%b4e -> δe.
        frag = urllib.parse.unquote(frag)

        return f'href={quote}#{html.escape(frag, quote=True)}{quote}'

    return re.sub(
        r'\bhref=(["\'])(.*?)\1',
        href_repl,
        content,
        flags=re.I | re.S,
    )    
    
def build_article_toc(content: str, page_id: str) -> str:
    headings = []

    for m in re.finditer(
        r'<h([2-4])\b([^>]*)>(.*?)</h\1>',
        content,
        flags=re.I | re.S,
    ):
        level = int(m.group(1))
        attrs = m.group(2)
        inner = m.group(3)
        text = html_to_plain_text(inner)

        if not text:
            continue

        id_match = re.search(r'\bid=(["\'])(.*?)\1', attrs, flags=re.I | re.S)

        if not id_match:
            continue

        heading_id = id_match.group(2)

        headings.append({
            "level": level,
            "text": text,
            "href": "#" + heading_id,
        })

    if len(headings) < 3:
        return ""

    out = []
    out.append('<div class="article-local-toc">')
    out.append('<div class="article-local-toc-title">Article Contents</div>')

    for h in headings:
        cls = f"article-local-toc-level-{h['level']}"
        out.append(
            f'<a class="{cls}" href="{html.escape(h["href"])}">'
            f'{html.escape(h["text"])}</a>'
        )

    out.append('</div>')

    return "\n".join(out)

def article_is_major(content: str, title: str = "") -> bool:
    """
    Decide whether an article is large enough to deserve a new page.

    Major articles:
      - have many headings / a substantial local TOC
      - or have a lot of body text
      - or are known major RawPedia reference articles

    Short articles with small TOCs should flow after a 1 inch spacer instead.
    """
    plain = html_to_plain_text(content)
    plain_len = len(plain)

    headings = re.findall(
        r"<h([2-4])\b[^>]*>.*?</h\1>",
        content,
        flags=re.I | re.S,
    )

    heading_count = len(headings)

    title_key = html.unescape(title or "").strip().lower()

    major_title_needles = [
        "color management",
        "exposure",
        "white balance",
        "preferences",
        "the image editor tab",
        "the file browser tab",
        "local adjustments",
        "wavelets",
        "sharpening",
        "noise reduction",
        "raw black and white points",
        "demosaicing",
        "film simulation",
        "dynamic processing profiles",
        "processing profiles",
        "toolchain pipeline",
        "cam16",
        "ciecam",
        "jz",
    ]

    if any(needle in title_key for needle in major_title_needles):
        return True

    if heading_count >= 8:
        return True

    if heading_count >= 5 and plain_len >= 4500:
        return True

    if plain_len >= 9000:
        return True

    return False

def has_meaningful_content(content: str, title: str = "") -> bool:
    if is_redirect_page_text(content, title):
        return False

    text = html_to_plain_text(content)

    if is_redirect_page_text(text, title):
        return False

    img_count = len(re.findall(r"<img\b|missing-image", content, flags=re.I))

    return len(text) >= 80 or img_count > 0

def compile_term_regex(term: str):
    escaped = re.escape(term)
    escaped = escaped.replace(r"\ ", r"\s+")
    return re.compile(rf"(?i)(?<![A-Za-z0-9]){escaped}(?![A-Za-z0-9])")

def title_contains_term(title: str, term: str) -> bool:
    title_key = re.sub(r"\s+", " ", html.unescape(title)).strip().lower()
    term_key = re.sub(r"\s+", " ", term).strip().lower()

    if title_key == term_key:
        return True

    if title_key.startswith(term_key + " "):
        return True

    if title_key.endswith(" " + term_key):
        return True

    return False

def extract_heading_terms(content: str) -> set[str]:
    terms = set()

    for m in re.finditer(r"<h[1-4]\b[^>]*>(.*?)</h[1-4]>", content, flags=re.I | re.S):
        heading = html_to_plain_text(m.group(1))
        heading = re.sub(r"\s+", " ", heading).strip()

        if 2 <= len(heading) <= 70:
            terms.add(heading)

    return terms

def extract_title_terms(title: str) -> set[str]:
    title = html.unescape(title).strip()
    out = set()

    if 2 <= len(title) <= 70:
        out.add(title)

    pieces = re.split(r"\s*(?:/|:|—|–|-|\(|\)|,)\s*", title)

    for p in pieces:
        p = re.sub(r"\s+", " ", p).strip()
        if 3 <= len(p) <= 50:
            out.add(p)

    return out

def extract_acronym_terms(text: str) -> set[str]:
    out = set()

    for m in re.finditer(r"\b[A-Z][A-Z0-9]{1,9}\b", text):
        token = m.group(0)
        if token in {"HTML", "HTTP", "HTTPS", "PDF", "PNG", "JPG", "JPEG", "GIF", "SVG"}:
            continue
        out.add(token)

    return out

def normalize_term(term: str) -> str:
    term = html.unescape(term)
    term = re.sub(r"\s+", " ", term).strip()
    term = term.strip(" \t\r\n:;,.!?()[]{}\"'")

    return term

def canonical_index_key(term: str) -> str:
    """
    Collapse duplicate index terms caused by case, punctuation, and simple plurals.
    """
    key = html.unescape(term or "")
    key = key.strip()
    key = re.sub(r"\s+", " ", key)
    key = key.lower()

    key = key.replace("–", "-")
    key = key.replace("—", "-")
    key = key.replace("_", " ")

    key = re.sub(r"\s*/\s*", "/", key)
    key = re.sub(r"\s*-\s*", "-", key)
    key = re.sub(r"[^a-z0-9+./* -]+", "", key)
    key = re.sub(r"\s+", " ", key).strip()

    words = key.split(" ")
    singular_words = []

    technical_singletons = {
        "raw", "rgb", "lab", "xyz", "icc", "dcp", "dng", "jpeg",
        "png", "tiff", "webp", "heif", "avif", "exif", "iptc",
        "xmp", "gps", "iso", "ev", "snr", "adc", "cfa", "psf",
        "otf", "mtf", "fft", "dft", "pca", "clahe", "lens",
        "focus", "alias", "aliases", "analysis", "series", "chassis",
        "canvas", "bias", "process", "access", "class", "glass",
    }

    es_singular_keep = (
        "ses",
        "xes",
        "zes",
        "ches",
        "shes",
    )

    for word in words:
        if word in technical_singletons:
            if word == "aliases":
                word = "alias"
            singular_words.append(word)
            continue

        # Simple plural folding, intentionally conservative.
        if len(word) > 4 and word.endswith("ies"):
            word = word[:-3] + "y"
        elif len(word) > 4 and word.endswith("ves"):
            word = word[:-3] + "f"
        elif len(word) > 4 and word.endswith(es_singular_keep):
            word = re.sub(r"es$", "", word)
        elif len(word) > 4 and word.endswith("s") and not word.endswith(("ss", "us", "is")):
            word = word[:-1]

        singular_words.append(word)

    key = " ".join(singular_words)
    key = re.sub(r"\s+", " ", key).strip()

    return key

def choose_index_display_term(existing: str, candidate: str) -> str:
    """
    Prefer a nice-looking index display term while using canonical_index_key()
    for duplicate detection.
    """
    if not existing:
        return candidate

    existing_seed = existing in technical_terms_seed
    candidate_seed = candidate in technical_terms_seed

    if candidate_seed and not existing_seed:
        return candidate

    if existing_seed and not candidate_seed:
        return existing

    if existing.islower() and not candidate.islower():
        return candidate

    if len(candidate) < len(existing):
        return candidate

    return existing

def build_all_technical_terms(infos):
    by_key = {}

    stop = {
        "Contents", "Overview", "Introduction", "General", "General Comments",
        "Main Page",
    }

    def add_term(term: str):
        term = normalize_term(term)

        if not term:
            return

        if term in stop:
            return

        if len(term) < 2 or len(term) > 70:
            return

        if re.search(r"^(the|and|or|for|with|from|this|that)\b", term, flags=re.I):
            return

        if re.fullmatch(r"\d+", term):
            return

        key = canonical_index_key(term)

        if not key:
            return

        old = by_key.get(key, "")
        by_key[key] = choose_index_display_term(old, term)

    for term in technical_terms_seed:
        add_term(term)

    for info in infos:
        for term in extract_title_terms(info["title"]):
            add_term(term)

        for term in extract_heading_terms(info["content"]):
            add_term(term)

        plain = html_to_plain_text(info["title"] + " " + info["content"])

        for term in extract_acronym_terms(plain):
            add_term(term)

    return sorted(by_key.values(), key=lambda s: s.lower())

def build_technical_index(infos):
    terms = build_all_technical_terms(infos)

    canonical_to_display = {}

    for term in terms:
        key = canonical_index_key(term)
        old = canonical_to_display.get(key, "")
        canonical_to_display[key] = choose_index_display_term(old, term)

    index = defaultdict(list)
    primary = defaultdict(set)

    term_regexes = []

    for display_term in canonical_to_display.values():
        key = canonical_index_key(display_term)

        variants = {
            display_term,
            display_term.lower(),
            display_term.upper(),
            display_term.title(),
        }

        if not display_term.lower().endswith("s"):
            variants.add(display_term + "s")
        elif len(display_term) > 3:
            variants.add(display_term[:-1])

        regexes = [
            compile_term_regex(v)
            for v in sorted(variants, key=len, reverse=True)
            if v
        ]

        term_regexes.append((display_term, key, regexes))

    for info in infos:
        text = html_to_plain_text(info["title"] + " " + info["content"])

        for display_term, key, regexes in term_regexes:
            if any(rx.search(text) for rx in regexes):
                index[key].append(info)

                if title_contains_term(info["title"], display_term):
                    primary[key].add(info["id"])

    result = {}

    seed_keys = {canonical_index_key(term) for term in technical_terms_seed}

    for key, refs in sorted(
        index.items(),
        key=lambda item: canonical_to_display.get(item[0], item[0]).lower(),
    ):
        if not refs:
            continue

        display_term = canonical_to_display.get(key, key)

        if key not in seed_keys and len(refs) < 2 and display_term.lower() not in html_to_plain_text(refs[0]["title"]).lower():
            continue

        seen = set()
        unique_refs = []

        for ref in refs:
            if ref["id"] in seen:
                continue

            seen.add(ref["id"])
            unique_refs.append(ref)

        result[display_term] = {
            "refs": unique_refs,
            "primary_ids": primary.get(key, set()),
        }

    return result

infos = []

for page in all_pages_raw:
    text = read_text(page)
    rel = rel_from_source(page)
    title = title_from_doc(text, rel)

    suppress, reason = should_suppress_page(title, rel, text)

    if suppress:
        if reason == "redirect":
            suppressed_redirects.append(rel)
        elif reason == "main-page-variant":
            suppressed_main_pages.append(rel)
        continue

    if not is_probably_english_page(page, title, text):
        continue

    page_id = make_id(rel)

    content = extract_main_or_body(text)
    content = strip_bad_parts(content)
    content = clean_links(content)

    if is_redirect_page_text(content, title):
        suppressed_redirects.append(rel)
        continue

    content = rewrite_images(content, page, title, rel)
    content = prefix_ids_and_anchors(content, page_id)
    content = strip_empty_leading_blocks(content)

    article_toc = build_article_toc(content, page_id)
    has_article_toc = bool(article_toc)

    if article_toc:
        content = article_toc + "\n" + content

    content = strip_empty_leading_blocks(content)

    if not has_meaningful_content(content, title):
        continue

    order, section = page_kind(title, rel)
    content_file = find_content_file_for_article_rel(rel)
    aliases = extract_aliases_from_content_file(content_file)

    github_url = github_url_for_article(title, rel)
    github_qr_uri = make_article_qr(page_id, github_url)

    infos.append({
        "path": page,
        "rel": rel,
        "id": page_id,
        "title": title,
        "section": section,
        "section_id": section_toc_id(section),
        "section_order": order,
        "has_article_toc": has_article_toc,
        "github_url": github_url,
        "github_qr_uri": github_qr_uri,
        "aliases": aliases,
        "content": content,
    })

infos.sort(key=page_sort_key)

for info in infos:
    expected_rel = choose_qr_content_rel(info["title"], info["rel"])

    if not expected_rel:
        continue

    if qr_rel_is_redirect(expected_rel):
        print()
        print("❌ QR post-sort resolver selected a redirect source file:")
        print(f"   title:  {info['title']}")
        print(f"   rel:    {info['rel']}")
        print(f"   source: content/{expected_rel}")
        print(f"   target: {qr_redirect_target_for_rel(expected_rel)}")
        sys.exit(1)

    expected_url = (
        "https://github.com/RawTherapee/RawPedia/blob/master/content/"
        + urllib.parse.quote(expected_rel, safe="/")
    )

    if info["github_url"] != expected_url:
        print(f"🔧 QR URL repaired: {info['github_url']} -> {expected_url}")
        info["github_url"] = expected_url
        info["github_qr_uri"] = make_article_qr(info["id"], expected_url)

manual_link_map = build_manual_link_map(infos)

qr_case_report = OUTPUT_HTML.parent / "article-github-source-map.txt"

qr_case_lines = []

for info in infos:
    url_path = urllib.parse.unquote(
        urllib.parse.urlsplit(info["github_url"]).path
    )

    content_rel = url_path.split("/content/", 1)[-1] if "/content/" in url_path else "[UNKNOWN]"

    qr_case_lines.append(f"{info['title']}")
    qr_case_lines.append(f"  generated: {info['rel']}")
    qr_case_lines.append(f"  source:    {content_rel}")
    qr_case_lines.append(f"  github:    {info['github_url']}")
    qr_case_lines.append("")

qr_case_report.write_text("\n".join(qr_case_lines), encoding="utf-8")
print(f"✅ Article GitHub source map report: {qr_case_report}")

bad_qr_sources = []

language_file_re = re.compile(
    r"/content/.*\.(fr|es|it|jp|ja|pt|de|ca|ct|zh|cn|ru|nl|pl|tr)\.(md|markdown|html)$",
    flags=re.I,
)

language_dir_re = re.compile(
    r"/content/(fr|es|it|jp|ja|pt|de|ca|ct|zh|cn|ru|nl|pl|tr)/",
    flags=re.I,
)

print("✅ QR GitHub source URLs are English-only")

bad_qr_redirect_sources = []

for info in infos:
    content_rel = choose_qr_content_rel(info["title"], info["rel"])

    if not content_rel:
        continue

    if qr_rel_is_redirect(content_rel):
        bad_qr_redirect_sources.append((info["title"], info["rel"], content_rel))

if bad_qr_redirect_sources:
    print()
    print("❌ QR resolver still selected redirect source files:")
    for title, rel, content_rel in bad_qr_redirect_sources[:120]:
        print(f"   {title}")
        print(f"     generated: {rel}")
        print(f"     source:    content/{content_rel}")
        print(f"     target:    {qr_redirect_target_for_rel(content_rel)}")
    sys.exit(1)

print("✅ QR resolver selected non-redirect source files")

for info in infos:
    url = info["github_url"]

    if language_file_re.search(url) or language_dir_re.search(url):
        bad_qr_sources.append((info["title"], info["rel"], url))

if bad_qr_sources:
    print()
    print("❌ QR GitHub source URLs point to translated source files:")
    
    for title, rel, url in bad_qr_sources[:80]:
        print(f"   {title}")
        print(f"     generated: {rel}")
        print(f"     github:    {url}")
    sys.exit(1)

print("✅ QR GitHub source URLs are English-only")
print("✅ Final QR resolver selected non-redirect source files")
print("✅ QR GitHub source URLs do not point to redirect source files")

for info in infos:
    info["content"] = rewrite_article_links_to_manual(
        info["content"],
        info["path"],
        manual_link_map,
    )

    info["content"] = normalize_internal_href_fragments(info["content"])

print(f"✅ Manual internal link routes mapped: {len(manual_link_map)}")
print(f"✅ CONTENTS_DIR used for QR source lookup: {CONTENTS_DIR}")
print(f"✅ CONTENTS_DIR exists: {CONTENTS_DIR.exists()}")

for contributor in harvest_contributors_from_contents():
    all_contributors.add(contributor)

authors_from_file = read_authors_file()
license_text, license_source = read_license_text()
technical_index = build_technical_index(infos)

contributors_sorted = sorted(
    all_contributors,
    key=lambda name: name.lower()
)

print(f"✅ English content pages selected: {len(infos)}")
print(f"✅ Redirect-like pages suppressed: {len(suppressed_redirects)}")
print(f"✅ Main Page variants suppressed: {len(suppressed_main_pages)}")
print(f"✅ Contributors found in ~/RawPedia/content markdown metadata: {len(contributors_sorted)}")
print(f"✅ Authors found in AUTHORS.txt: {len(authors_from_file)}")
print(f"✅ Index of technical terms with hits: {len(technical_index)}")
print(f"✅ Cover icon source: {RT_COVER_PNG}")
print(f"✅ Header TOC icon source: {RT_HEADER_PNG}")
print(f"✅ RawPedia QR code source: {RAWPEDIA_QR_SVG}")

if suppressed_redirects:
    report = OUTPUT_HTML.parent / "suppressed-redirect-pages.txt"
    report.write_text("\n".join(sorted(set(suppressed_redirects))) + "\n", encoding="utf-8")
    print(f"✅ Suppressed redirect report: {report}")

if suppressed_main_pages:
    report = OUTPUT_HTML.parent / "suppressed-main-pages.txt"
    report.write_text("\n".join(sorted(set(suppressed_main_pages))) + "\n", encoding="utf-8")
    print(f"✅ Suppressed Main Page variants report: {report}")

if contributors_sorted:
    report = OUTPUT_HTML.parent / "contributors.txt"
    report.write_text("\n".join(contributors_sorted) + "\n", encoding="utf-8")
    print(f"✅ Contributor report: {report}")

if authors_from_file:
    report = OUTPUT_HTML.parent / "authors.txt"
    report.write_text("\n".join(authors_from_file) + "\n", encoding="utf-8")
    print(f"✅ AUTHORS.txt report: {report}")

if technical_index:
    report = OUTPUT_HTML.parent / "technical-index-terms.txt"
    lines = []

    for term, data in technical_index.items():
        lines.append(term)

        for ref in data["refs"]:
            marker = " *" if ref["id"] in data["primary_ids"] else ""
            lines.append(f"  - {ref['title']} [{ref['rel']}]{marker}")

    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"✅ Index of technical terms report: {report}")

contributors_display = ", ".join(contributors_sorted)

if not contributors_display:
    contributors_display = "No contributor metadata was found in ~/RawPedia/content."

authors_display = ", ".join(authors_from_file)

if not authors_display:
    authors_display = "No AUTHORS.txt data was found at ~/repo-rt/AUTHORS.txt."

license_html = license_text_to_html_paragraphs(license_text)

with OUTPUT_HTML.open("w", encoding="utf-8") as out:
    out.write(f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>RawTherapee Manual</title>
<style>

@page {{
  size: 8.125in 10.25in;
  margin-top: 0.72in;
  margin-right: 0.9in;
  margin-bottom: 0.72in;
  margin-left: 0.5in;

  @top-left {{
    content: element(bookHeader);
    width: 2.1in;
  }}

  @top-center {{
    content: element(sectionLink);
  }}

  @top-right {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-left {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-center {{
    content: element(articleFooter);
  }}

  @bottom-right {{
    content: "";
  }}
}}

@page :left {{
  margin-top: 0.72in;
  margin-right: 0.5in;
  margin-bottom: 0.72in;
  margin-left: 0.9in;
}}

@page :right {{
  margin-top: 0.72in;
  margin-right: 0.9in;
  margin-bottom: 0.72in;
  margin-left: 0.5in;
}}

@page cover {{
  size: 8.125in 10.25in;
  margin: 0;

  @top-left {{ content: ""; }}
  @top-center {{ content: ""; }}
  @top-right {{ content: ""; }}
  @bottom-left {{ content: ""; }}
  @bottom-center {{ content: ""; }}
  @bottom-right {{ content: ""; }}
}}

@page finalpage {{
  size: 8.125in 10.25in;
  margin: 0;

  @top-left {{ content: ""; }}
  @top-center {{ content: ""; }}
  @top-right {{ content: ""; }}
  @bottom-left {{ content: ""; }}
  @bottom-center {{ content: ""; }}
  @bottom-right {{ content: ""; }}
}}

.final-icon-page {{
  page: finalpage;
  break-before: page;
  break-after: page;
  width: 8.125in;
  height: 10.25in;
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  justify-content: center;
  background: white;
  string-set: article "";
}}

.final-icon-page img {{
  width: 5in;
  height: 5in;
  object-fit: contain;
  background: transparent;
}}

.final-icon-page {{
  page: finalpage;
  break-before: page;
  height: 9.56in;
  display: flex;
  align-items: center;
  justify-content: center;
  string-set: article "";
}}

.final-icon-page img {{
  width: 5in;
  height: 5in;
  object-fit: contain;
  background: transparent;
}}

.intentional-blank-page {{
  page: intentionalblank;
  break-before: auto;
  break-after: page;
  width: 8.125in;
  height: 10.25in;
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  background: white;
  string-set: article "";
}}

.intentional-blank-page img {{
  width: 1in;
  height: 1in;
  object-fit: contain;
  background: transparent;
}}

.final-blank-before-icon {{
  break-before: page;
}}

@page frontmatter {{
  size: 8.125in 10.25in;
  margin: 0.805in 0.805in 0.805in 0.805in;

  @top-left {{
    content: element(bookHeader);
    width: 2.1in;
  }}

  @top-center {{
    content: "RawTherapee Manual";
    font-family: Helvetica, Arial, sans-serif;
    font-size: 7.5pt;
    color: #666;
  }}

  @top-right {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-left {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-center {{
    content: string(article);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 7.5pt;
    color: #666;
  }}

  @bottom-right {{
    content: "";
  }}
}}

@page frontmatter:left {{
  margin-top: 0.72in;
  margin-right: 0.5in;
  margin-bottom: 0.72in;
  margin-left: 0.9in;
}}

@page frontmatter:right {{
  margin-top: 0.72in;
  margin-right: 0.9in;
  margin-bottom: 0.72in;
  margin-left: 0.5in;
}}

@page tocpage {{
  size: 8.125in 10.25in;
  margin: 0.805in 0.805in 0.805in 0.805in;

  @top-left {{
    content: element(bookHeader);
    width: 2.1in;
  }}

  @top-center {{
    content: "Contents";
    font-family: Helvetica, Arial, sans-serif;
    font-size: 7.5pt;
    color: #666;
  }}

  @top-right {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-left {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-center {{
    content: "Contents";
    font-family: Helvetica, Arial, sans-serif;
    font-size: 7.5pt;
    color: #666;
  }}

  @bottom-right {{
    content: "";
  }}
}}

@page tocpage:left {{
  margin-top: 0.62in;
  margin-right: 0.5in;
  margin-bottom: 0.68in;
  margin-left: 0.9in;
}}

@page tocpage:right {{
  margin-top: 0.62in;
  margin-right: 0.9in;
  margin-bottom: 0.68in;
  margin-left: 0.5in;
}}

@page intentionalblank {{
  size: 8.125in 10.25in;
  margin: 0;

  @top-left {{ content: ""; }}
  @top-center {{ content: ""; }}
  @top-right {{ content: ""; }}
  @bottom-left {{ content: ""; }}
  @bottom-center {{ content: ""; }}
  @bottom-right {{ content: ""; }}
}}

@page indexpage {{
  size: 8.125in 10.25in;
  margin: 0.805in 0.805in 0.805in 0.805in;

  @top-left {{
    content: element(bookHeader);
    width: 2.1in;
  }}

  @top-center {{
    content: "Index of Technical Terms";
    font-family: Helvetica, Arial, sans-serif;
    font-size: 7.5pt;
    color: #666;
  }}

  @top-right {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-left {{
    content: counter(page);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 8pt;
    color: #555;
  }}

  @bottom-center {{
    content: element(articleFooter);
  }}

  @bottom-right {{
    content: "";
  }}
}}

@page indexpage:left {{
  margin-top: 0.62in;
  margin-right: 0.5in;
  margin-bottom: 0.68in;
  margin-left: 0.9in;
}}

@page indexpage:right {{
  margin-top: 0.62in;
  margin-right: 0.9in;
  margin-bottom: 0.68in;
  margin-left: 0.5in;
}}

html, body {{
  font-family: Georgia, "Times New Roman", serif;
  font-size: 8.6pt;
  line-height: 1.14;
  color: #111;
}}

body {{
  margin: 0;
}}

.running-book-header {{
  position: running(bookHeader);
  display: block;
  width: 2.1in;
  height: 0.32in;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 6.7pt;
  line-height: 1.05;
  color: #666;
}}

.running-book-header a {{
  display: flex;
  align-items: center;
  gap: 0.055in;
  color: #666;
  text-decoration: none;
}}

.running-book-header img {{
  width: 0.30in;
  height: 0.30in;
  object-fit: contain;
  background: transparent;
  display: block;
  flex: 0 0 auto;
}}

.book-header-text {{
  display: block;
  white-space: nowrap;
}}

.book-header-title {{
  display: block;
  font-weight: bold;
}}

.book-header-date {{
  display: block;
  font-size: 6.2pt;
  color: #777;
}}

.running-article-footer {{
  position: running(articleFooter);
  font-family: Helvetica, Arial, sans-serif;
  font-size: 7.5pt;
  color: #666;
  text-align: center;
  white-space: nowrap;
}}

.running-article-footer a {{
  color: #666;
  text-decoration: none;
}}

.running-section-link {{
  position: running(sectionLink);
  font-family: Helvetica, Arial, sans-serif;
  font-size: 7.5pt;
  color: #666;
  text-align: center;
  white-space: nowrap;
}}

.running-section-link a {{
  color: #666;
  text-decoration: none;
}}

.blank-page {{
  page: blankpage;
  break-before: page;
  min-height: 9.0in;
}}

.blank-page + .blank-page {{
  break-before: page;
}}

@page blankpage {{
  size: 8.125in 10.25in;
  margin: 0;

  @top-left {{ content: ""; }}
  @top-center {{ content: ""; }}
  @top-right {{ content: ""; }}
  @bottom-left {{ content: ""; }}
  @bottom-center {{ content: ""; }}
  @bottom-right {{ content: ""; }}
}}

.article-github-qr {{
  break-inside: avoid;
  margin: 0.18in 0 0 0;
  padding: 0.08in 0.1in;
  border-top: 0.45pt solid #bbb;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 6.7pt;
  line-height: 1.15;
  color: #555;
  text-align: center;
}}

.article-github-qr-title {{
  font-weight: bold;
  color: #333;
  margin-bottom: 0.045in;
}}

.article-github-qr img {{
  width: 0.72in;
  height: 0.72in;
  object-fit: contain;
  background: transparent;
  display: block;
  margin: 0 auto 0.045in auto;
}}

.article-github-qr-url {{
  overflow-wrap: anywhere;
}}

.cover {{
  page: cover;
  width: 8.125in;
  height: 10.25in;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  justify-content: center;
  text-align: center;
  break-after: page;
  background: #000000;
  color: #fff;
  margin: 0;
  padding: 0.95in;
}}

.cover-icon-frame {{
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: #101521;
  border-radius: 0.45in;
  padding: 0.26in;
  margin: 0 auto 0.45in auto;
  border-top: 5pt solid #8db8ff;
  border-left: 5pt solid #5f8fe8;
  border-right: 5pt solid #1f3e7a;
  border-bottom: 5pt solid #14213d;
}}

.cover-icon-frame a {{
  display: block;
}}

.cover-icon {{
  width: 3.25in;
  height: 3.25in;
  object-fit: contain;
  display: block;
}}

.cover-title-stack {{
  position: relative;
  width: 100%;
  height: 1.18in;
  margin: 0 0 0.15in 0;
}}

.cover-title-layer,
.cover-title-front {{
  position: absolute;
  left: 0;
  top: 0;
  width: 100%;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 36pt;
  line-height: 1.02;
  font-weight: bold;
  letter-spacing: -0.02em;
  margin: 0;
  text-align: center;
}}

.cover-title-back-3 {{
  color: #14213d;
  left: 2.4pt;
  top: 2.4pt;
}}

.cover-title-back-2 {{
  color: #334a78;
  left: 1.6pt;
  top: 1.6pt;
}}

.cover-title-back-1 {{
  color: #7fa8e8;
  left: 0.8pt;
  top: 0.8pt;
}}

.cover-title-front {{
  color: #f8fbff;
  left: 0;
  top: 0;
}}

.cover-date-stack {{
  position: relative;
  width: 100%;
  height: 0.34in;
  margin: 0 0 0.18in 0;
}}

.cover-date-layer,
.cover-date {{
  position: absolute;
  left: 0;
  top: 0;
  width: 100%;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 22pt;
  line-height: 1.05;
  text-align: center;
}}

.cover-date-back {{
  color: #26334b;
  left: 0.7pt;
  top: 0.7pt;
}}

.cover-date {{
  color: #dce8ff;
}}

.subtitle-stack {{
  position: relative;
  width: 100%;
  height: 0.26in;
  margin-top: 0.06in;
}}

.subtitle-layer,
.cover .subtitle {{
  position: absolute;
  left: 0;
  top: 0;
  width: 100%;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 15pt;
  text-align: center;
}}

.subtitle-back {{
  color: #26334b;
  left: 0.55pt;
  top: 0.55pt;
}}

.cover .subtitle {{
  color: #dce8ff;
}}

.cover .edition {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 9.5pt;
  color: #aac2e8;
  margin-top: 0.35in;
}}

.half-title-git-version {{
  font-size: 11pt;
  line-height: 1.15;
  font-weight: bold;
  margin: 0.45in auto 0 auto;
  width: 5.4in;
}}

.copyright-page {{
  page: frontmatter;
  break-after: page;
  font-size: 11.2pt;
  line-height: 1.35;
  string-set: article "Copyright";
}}

.copyright-inner {{
  margin-top: 1.35in;
}}

.contributor-list,
.authors-list {{
  font-size: 11.2pt;
  line-height: 1.18;
  color: #333;
  margin-top: 0.1in;
  overflow-wrap: anywhere;
}}

.license-page {{
  page: frontmatter;
  break-after: page;
  string-set: article "License";
}}

.license-page h1 {{
  font-size: 14pt;
  margin: 0 0 0.045in 0;
}}

.license-text {{
  column-count: 2;
  column-gap: 0.11in;
  column-rule: 0.5pt solid #ddd;
  white-space: normal;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 5pt;
  line-height: 1.09;
  text-align: justify;
  overflow-wrap: normal;
  word-break: normal;
}}

.license-text p {{
  margin: 0 0 0.45em 0;
  text-indent: 0.08in;
}}

.license-text p:first-child {{
  text-indent: 0;
}}

.license-heading {{
  break-after: avoid;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 5.4pt;
  line-height: 1.05;
  font-weight: bold;
  text-align: left;
  letter-spacing: 0.025em;
  margin: 0.35em 0 0.16em 0;
}}

.half-title {{
  page: frontmatter;
  break-after: page;
  text-align: center;
  padding-top: 3.2in;
  string-set: article "Half Title";
}}

.half-title h1 {{
  font-size: 26pt;
  margin-bottom: 0.2in;
}}

.preface {{
  page: frontmatter;
  break-after: page;
  string-set: article "Preface";
}}

.preface h1 {{
  font-size: 20pt;
  margin: 0 0 0.2in 0;
}}

.preface-git-version {{
  font-size: 15pt;
  line-height: 1.15;
  font-weight: bold;
  margin: 0 0 0.28in 0;
}}

.preface-qr-block {{
  text-align: center;
  margin: 0.22in auto 0.32in auto;
  break-inside: avoid;
}}

.preface-qr-title {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 21pt;
  line-height: 1.15;
  font-weight: bold;
  color: #111;
  margin: 0 0 0.16in 0;
}}

.preface-qr-image {{
  width: 2.65in;
  height: 2.65in;
  object-fit: contain;
}}

.preface-qr-url {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 10pt;
  color: #555;
  margin-top: 0.08in;
}}

.toc-section-wrapper {{
  page: tocpage;
  break-after: page;
  string-set: article "Contents";
}}

.toc-section-wrapper h1 {{
  font-size: 24pt;
  margin: 0 0 0.25in 0;
}}

.toc {{
  font-family: Georgia, "Times New Roman", serif;
  font-size: 9.2pt;
  line-height: 1.28;
}}

.toc-part {{
  break-inside: avoid;
  margin: 0 0 0.18in 0;
}}

.toc h2 {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 10.2pt;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin: 0.22in 0 0.08in 0;
  border-bottom: 0.5pt solid #999;
  padding-bottom: 0.03in;
}}

.toc a {{
  display: block;
  color: #111;
  text-decoration: none;
  margin: 0 0 0.035in 0;
}}

.toc a::after {{
  content: leader(".") target-counter(attr(href), page);
}}

.part-page {{
  break-before: page;
  break-after: page;
  height: 9in;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  string-set: article "RawTherapee Manual";
}}

.part-page-icon {{
  width: 1in;
  height: 1in;
  object-fit: contain;
  background: transparent;
  margin: 0 auto 0.28in auto;
  display: block;
}}

.part-page-inner {{
  width: 5.9in;
  text-align: center;
  transform: translateY(-0.18in);
}}

.part-page .part-kicker {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 9pt;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #777;
  margin-bottom: 0.12in;
}}

.part-page h1 {{
  font-size: 27pt;
  line-height: 1.05;
  margin: 0;
}}

.part-subtoc {{
  margin: 0.28in auto 0 auto;
  padding: 0.13in 0.18in;
  width: 5.25in;
  border: 0.75pt solid #777;
  background: #f7f7f7;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 7.4pt;
  line-height: 1.18;
  text-align: left;
  break-inside: avoid;
}}

.part-subtoc-title {{
  text-align: center;
  font-weight: bold;
  font-size: 8.2pt;
  text-transform: uppercase;
  letter-spacing: 0.045em;
  color: #444;
  margin: 0 0 0.06in 0;
}}

.part-subtoc-body {{
  column-count: 2;
  column-gap: 0.18in;
}}

.part-subtoc a {{
  display: block;
  color: #111;
  text-decoration: none;
  margin: 0 0 0.025in 0;
}}

.part-subtoc a::after {{
  content: leader(".") target-counter(attr(href), page);
}}

.article {{
  break-before: auto;
  margin-top: 1.35in;
  string-set: article attr(data-title);
}}

.article.first-article {{
  margin-top: 0;
}}

.article.major-article {{
  break-before: page;
  margin-top: 0;
}}

.article.short-article {{
  break-before: auto;
  margin-top: 1in;
}}

.article h1.article-title {{
  font-size: 15.5pt;
  line-height: 1.04;
  margin: 0 0 0.11in 0;
  padding-bottom: 0.04in;
  border-bottom: 0.6pt solid #999;
}}

.section-label {{
  font-size: 7.5pt;
  font-family: Helvetica, Arial, sans-serif;
  text-transform: uppercase;
  color: #666;
  letter-spacing: 0.04em;
  margin-bottom: 0.05in;
}}

.article-body {{
  column-count: 2;
  column-gap: 1.18em;
  column-rule: 0.25pt solid #ccc;
  min-height: 0;
  text-align: justify;
  hyphens: auto;
}}

.article-body p,
.article-body li {{
  text-align: justify;
  hyphens: auto;
}}

.article-body h1,
.article-body h2,
.article-body h3,
.article-body h4,
.article-body pre,
.article-body code,
.article-body table,
.article-body .article-local-toc,
.article-body .missing-image {{
  text-align: left;
  hyphens: manual;
}}

.article-body > :first-child {{
  break-before: auto !important;
  page-break-before: auto !important;
  margin-top: 0 !important;
}}

.article-body > :first-child,
.article-body > :first-child * {{
  break-before: auto !important;
  page-break-before: auto !important;
}}

.article-body > figure:first-child,
.article-body > table:first-child,
.article-body > pre:first-child,
.article-body > blockquote:first-child,
.article-body > div:first-child {{
  break-inside: auto !important;
  page-break-inside: auto !important;
}}

.article-local-toc {{
  break-inside: avoid;
  border: 0.45pt solid #bbb;
  background: #f7f7f7;
  padding: 0.08in 0.1in;
  margin: 0 0 0.16in 0;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 7.8pt;
  line-height: 1.22;
}}

.article-local-toc-title {{
  font-weight: bold;
  font-size: 8.6pt;
  margin: 0 0 0.045in 0;
  color: #333;
}}

.article-local-toc a {{
  display: block;
  color: #111;
  text-decoration: none;
  margin: 0 0 0.025in 0;
}}

.article-local-toc a::after {{
  content: leader(".") target-counter(attr(href), page);
}}

.article-local-toc-level-2 {{
  margin-left: 0;
}}

.article-local-toc-level-3 {{
  margin-left: 0.12in;
  font-size: 7.5pt;
}}

.article-local-toc-level-4 {{
  margin-left: 0.24in;
  font-size: 7.2pt;
  color: #444;
}}

.article-body h1,
.article-body h2,
.article-body h3,
.article-body h4 {{
  break-after: avoid;
  break-before: auto;
  line-height: 1.1;
}}

.article-body h1 {{
  font-size: 12.8pt;
  margin: 0.38em 0 0.16em 0;
}}

.article-body h2 {{
  font-size: 11.2pt;
  margin: 0.34em 0 0.14em 0;
}}

.article-body h3 {{
  font-size: 9.8pt;
  margin: 0.28em 0 0.11em 0;
}}

.article-body h4 {{
  font-size: 9.1pt;
  margin: 0.22em 0 0.08em 0;
}}

.dereferenced-mediawiki-image {{
  margin: 0.08in 0 0.12in 0;
  padding: 0;
  break-inside: avoid;
  text-align: center;
}}

.dereferenced-mediawiki-image img {{
  max-width: 100%;
  height: auto;
  object-fit: contain;
}}

p {{
  margin: 0 0 0.24em 0;
}}

ul, ol {{
  margin-top: 0.08em;
  margin-bottom: 0.24em;
  padding-left: 1.05em;
}}

li {{
  margin: 0 0 0.08em 0;
}}

img, svg {{
  max-width: 100%;
  height: auto;
  break-inside: avoid;
}}

figure, table, pre, blockquote, .missing-image {{
  break-inside: auto;
}}

table {{
  width: 100%;
  border-collapse: collapse;
  font-size: 6.9pt;
}}

td, th {{
  border: 0.3pt solid #ccc;
  padding: 1.4px 2px;
  vertical-align: top;
}}

pre {{
  background: #f5f5f5;
  border: 0.3pt solid #ddd;
  padding: 0.32em;
  white-space: pre-wrap;
  overflow-wrap: break-word;
  font-size: 6.4pt;
  line-height: 1.04;
}}

code {{
  font-family: Menlo, Consolas, monospace;
  font-size: 6.7pt;
  background: #eee;
  padding: 0 1.5px;
}}

a {{
  color: #0645ad;
  text-decoration: none;
}}

hr {{
  border: none;
  border-top: 0.5pt solid #999;
  margin: 0.2in 0;
}}

.missing-image {{
  border: 0.8pt dashed #999;
  background: #f4f4f4;
  color: #555;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 8pt;
  text-align: center;
  padding: 0.22in 0.08in;
  margin: 0.08in 0;
}}

.missing-image strong {{
  color: #800;
}}

.missing-file {{
  font-weight: bold;
  margin-top: 0.05in;
}}

.missing-path {{
  font-size: 6.8pt;
  color: #777;
  overflow-wrap: anywhere;
}}

.technical-index {{
  page: indexpage;
  break-before: page;
  string-set: article "Index of Technical Terms";
}}

.technical-index h1 {{
  font-size: 24pt;
  margin: 0 0 0.25in 0;
}}

.blank-page {{
  break-before: page;
  height: 9in;
}}

.blank-page + .blank-page {{
  break-before: page;
}}

.index-note {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 8pt;
  color: #666;
  margin: 0 0 0.18in 0;
}}

.index-body {{
  columns: 4;
  column-count: 4;
  column-width: 1.15in;
  column-gap: 0.06in;
  column-rule: 0.25pt solid #ccc;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 5.4pt;
  line-height: 1.03;
}}

.index-letter {{
  break-after: avoid;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 7.6pt;
  font-weight: bold;
  margin: 0.055in 0 0.018in 0;
  border-bottom: 0.3pt solid #aaa;
}}

.index-entry {{
  break-inside: auto;
  page-break-inside: auto;
  margin: 0 0 0.01in 0;
}}

.index-term {{
  font-weight: bold;
}}

.index-pages {{
  margin-left: 0.035in;
}}

.index-pages a {{
  color: #111;
  text-decoration: none;
}}

.index-pages a::after {{
  content: target-counter(attr(href), page);
}}

.index-pages a.primary::after {{
  font-weight: bold;
}}

.index-pages a + a::before {{
  content: ", ";
}}
</style>
</head>
<body>
""")

    out.write(f"""
<section class="cover">
<div class="cover-icon-frame">
  <a href="#contents">
    <img class="cover-icon" src="{html.escape(RT_COVER_URI, quote=True)}" alt="RawTherapee icon">
  </a>
</div>
<div class="cover-title-stack" aria-label="RawTherapee Manual">
  <div class="cover-title-layer cover-title-back-3">RawTherapee Manual</div>
  <div class="cover-title-layer cover-title-back-2">RawTherapee Manual</div>
  <div class="cover-title-layer cover-title-back-1">RawTherapee Manual</div>
  <h1 class="cover-title-front">RawTherapee Manual</h1>
</div>

<div class="cover-date-stack" aria-label="{html.escape(BUILD_DATE)}">
  <div class="cover-date-layer cover-date-back">{html.escape(BUILD_DATE)}</div>
  <div class="cover-date">{html.escape(BUILD_DATE)}</div>
</div>

<div class="subtitle-stack" aria-label="A book-style local reference for RawTherapee">
  <div class="subtitle-layer subtitle-back">A book-style local reference for RawTherapee</div>
  <div class="subtitle">A book-style local reference for RawTherapee</div>
</div>
<div class="edition">Compiled from a local RAWPedia mirror</div>
</section>

<div class="running-book-header">
  <a href="#contents">
    <img src="{html.escape(RT_HEADER_URI, quote=True)}" alt="Contents">
    <span class="book-header-text">
      <span class="book-header-title">RawTherapee Manual</span>
      <span class="book-header-date">{html.escape(BUILD_DATE)}</span>
    </span>
  </a>
</div>
""")

    out.write(f"""
<section class="half-title">
<h1>RawTherapee Manual</h1>
<p>A local manual generated from RAWPedia.</p>

<div class="git-version-box half-title-git-version">
  <div>{html.escape(RT_GIT_VERSION)}</div>
  <div>{html.escape(RAWPEDIA_GIT_VERSION)}</div>
</div>
</section>

<section class="intentional-blank-page" aria-label="This page intentionally left blank">
  <img src="{html.escape(RT_HEADER_URI, quote=True)}" alt="">
</section>
""")

    out.write(f"""
<section class="copyright-page">
<div class="copyright-inner">
<p><strong>RawTherapee Manual</strong></p>
<p>© {html.escape(COPYRIGHT_YEAR)} RawPedia Contributors and the RawTherapee Development Team.</p>
<p>Compiled from a local RAWPedia mirror for offline reference and print-style reading.</p>
<p>This generated manual is an unofficial compilation of locally built RAWPedia pages. RawTherapee and RAWPedia names and materials remain the property of their respective contributors and projects.</p>
<p>Generated for private reference use. Please consult the RawTherapee project and RAWPedia source materials for authoritative licensing and attribution information.</p>
<p><strong>RawPedia contributors found recursively in ~/RawPedia/content Hugo metadata:</strong></p>
<p class="contributor-list">{html.escape(contributors_display)}</p>
<p><strong>RawTherapee authors from ~/repo-rt/AUTHORS.txt:</strong></p>
<p class="authors-list">{html.escape(authors_display)}</p>
</div>
</section>
""")

    out.write(f"""
<section class="license-page">
<h1>License</h1>
<div class="license-text">{license_html}</div>
</section>
""")

    out.write(f"""
<section class="preface">
<p style="text-align:center; margin-bottom:0.35in;">
  <a href="#contents">
    <img src="{html.escape(RT_COVER_URI, quote=True)}" style="width:1.2in; height:1.2in; object-fit:contain; background:#1d1d1d; border-radius:0.16in; padding:0.08in;" alt="Contents">
  </a>
</p>
<h1>Reference Versions at Buildtime</h1>
<div class="git-version-box preface-git-version">
  <div>{html.escape(RT_GIT_VERSION)}</div>
  <div>{html.escape(RAWPEDIA_GIT_VERSION)}</div>
</div>

<div class="preface-qr-block">
  <div class="preface-qr-title">Scan the QR code to go to RawPedia online.</div>
  <a href="{html.escape(RAWPEDIA_ONLINE_URL, quote=True)}">
    <img class="preface-qr-image" src="{html.escape(RAWPEDIA_QR_URI, quote=True)}" alt="RawPedia online QR code">
  </a>
  <div class="preface-qr-url">{html.escape(RAWPEDIA_ONLINE_URL)}</div>
</div>

<p>This manual arranges English RAWPedia pages into a book-like order, beginning with installation and workflow, then moving through raw development, tone, color, detail, geometry, local editing, and advanced reference material.</p>
<p>The body is set in two columns to make better use of printed page space. The table of contents includes printed page numbers as well as clickable links in PDF readers.</p>
<p>Missing image references are shown inline as placeholder boxes with the original filename, so broken assets are visible instead of silently disappearing.</p>
</section>
""")

    out.write("""
<section class="toc-section-wrapper" id="contents">
<h1>Contents</h1>
<div class="toc">
""")

    current_section = None

    for info in infos:
        section = info["section"]
        section_id = info["section_id"]

        if section != current_section:
            if current_section is not None:
                out.write("</div>\n")
            out.write('<div class="toc-part">\n')
            out.write(f'<h2 id="{html.escape(section_id)}">{html.escape(section)}</h2>\n')
            current_section = section

        out.write(
            f'<a href="#page-{html.escape(info["id"])}">'
            f'{html.escape(info["title"])}</a>\n'
        )

    if current_section is not None:
        out.write("</div>\n")

    out.write("""
<div class="toc-part">
<h2>Back Matter</h2>
<a href="#technical-index">Index of Technical Terms</a>
</div>
""")

    out.write("""
</div>
</section>
""")

    section_infos = defaultdict(list)

    for section_info in infos:
        section_infos[section_info["section"]].append(section_info)

    def build_part_subtoc(section: str) -> str:
        refs = section_infos.get(section, [])

        if not refs:
            return ""

        lines = []
        lines.append('<div class="part-subtoc">')
        lines.append('<div class="part-subtoc-title">In this section</div>')
        lines.append('<div class="part-subtoc-body">')

        for ref in refs:
            lines.append(
                f'<a href="#page-{html.escape(ref["id"])}">'
                f'{html.escape(ref["title"])}</a>'
            )

        lines.append('</div>')
        lines.append('</div>')

        return "\n".join(lines)

    current_section = None
    part_num = 0
    article_num = 0
    for info in infos:
        section = info["section"]
        section_id = info["section_id"]

        if section != current_section:
            current_section = section
            part_num += 1

            part_subtoc = build_part_subtoc(section)

            out.write(f"""
<div class="running-section-link">
  <a href="#{html.escape(section_id)}">{html.escape(section)}</a>
</div>
<div class="running-article-footer">
  <a href="#contents">RawTherapee Manual</a>
</div>
<section class="part-page">
<div class="part-page-inner">
  <img class="part-page-icon" src="{html.escape(RT_HEADER_URI, quote=True)}" alt="">
  <div class="part-kicker">Section {part_num}</div>
  <h1>{html.escape(section)}</h1>
  {part_subtoc}
</div>
</section>
""")
        else:
            out.write(f"""
<div class="running-section-link">
  <a href="#{html.escape(section_id)}">{html.escape(section)}</a>
</div>
""")

        print(f"  ➜ [{section}] {info['title']}")

        article_num += 1

        article_classes = ["article"]

        if article_num == 1:
            article_classes.append("first-article")
        elif article_is_major(info["content"], info["title"]):
            article_classes.append("major-article")
        else:
            article_classes.append("short-article")

        article_class = " ".join(article_classes)

        out.write(f"""
<div class="running-article-footer">
  <a href="#page-{html.escape(info["id"])}">{html.escape(info["title"])}</a>
</div>
<section id="page-{html.escape(info["id"])}" class="{article_class}" data-section="{html.escape(section)}" data-title="{html.escape(info["title"])}">
<div class="section-label">{html.escape(section)}</div>
<h1 class="article-title">{html.escape(info["title"])}</h1>
<div class="article-body">
{info["content"]}

<div class="article-github-qr">
  <div class="article-github-qr-title">Source article on GitHub</div>
  <a href="{html.escape(info["github_url"], quote=True)}">
    <img src="{html.escape(info["github_qr_uri"], quote=True)}" alt="GitHub source QR code">
  </a>
  <div class="article-github-qr-url">{html.escape(info["github_url"])}</div>
</div>
</div>
</section>
""")

    out.write("""
<div class="running-article-footer">
  <a href="#technical-index">Index of Technical Terms</a>
</div>
<section class="technical-index" id="technical-index">
<h1>Index of Technical Terms</h1>
<p class="index-note">Bold page numbers mark pages where the indexed term appears to begin a main article. Case variants and simple plural spellings are folded into one index entry. Page numbers are generated by the PDF renderer. True condensed page ranges require a second pass after final pagination; WeasyPrint target counters cannot compute ranges directly.</p>
<div class="index-body">
""")

    last_letter = None

    for term, data in technical_index.items():
        refs = data["refs"]
        primary_ids = data["primary_ids"]
        first_letter = term[0].upper()

        if first_letter != last_letter:
            last_letter = first_letter
            out.write(f'<div class="index-letter">{html.escape(first_letter)}</div>\n')

        out.write('<div class="index-entry">')
        out.write(f'<span class="index-term" id="{html.escape(term_id(term))}">{html.escape(term)}</span>')
        out.write('<span class="index-pages"> ')

        seen_refs = set()

        for ref in refs:
            href = f"#page-{ref['id']}"

            if href in seen_refs:
                continue

            seen_refs.add(href)

            cls = ' class="primary"' if ref["id"] in primary_ids else ""
            out.write(f'<a{cls} href="{html.escape(href)}" title="{html.escape(ref["title"])}"></a>')

        out.write('</span>')
        out.write('</div>\n')

    out.write("""
</div>
</section>
""")

    out.write("""
</body>
</html>
""")


html_text = OUTPUT_HTML.read_text(encoding="utf-8", errors="replace")

total_img_tags = len(re.findall(r"<img\b", html_text, flags=re.I))
file_image_refs = len(re.findall(r'src=["\']file://', html_text, flags=re.I))
missing_image_boxes = len(re.findall(r'class=["\']missing-image["\']', html_text, flags=re.I))

print(f"✅ HTML image tags: {total_img_tags}")
print(f"✅ HTML local file image refs: {file_image_refs}")
print(f"✅ HTML missing-image placeholders: {missing_image_boxes}")

if total_img_tags < 20:
    print("❌ Suspiciously few image tags in generated HTML.")
    print("❌ The PDF will be mostly text if this continues.")
    sys.exit(1)

if file_image_refs < 20:
    print("❌ Suspiciously few local file:// image references in generated HTML.")
    print("❌ Images are probably not being resolved from ~/RawPedia/Public.")
    sys.exit(1)

if missing_images:
    report = OUTPUT_HTML.parent / "missing-images.txt"

    seen = set()
    unique_entries = []

    for item in missing_images:
        key = (
            item["image"],
            item["filename"],
            item["page_title"],
            item["page_rel"],
        )

        if key in seen:
            continue

        seen.add(key)
        unique_entries.append(item)

    unique_entries.sort(
        key=lambda item: (
            item["filename"].lower(),
            item["page_title"].lower(),
            item["image"].lower(),
            item["page_rel"].lower(),
        )
    )

    lines = []
    lines.append("RawTherapee Manual Missing Image Report")
    lines.append("=======================================")
    lines.append("")
    lines.append(f"Missing image references: {len(unique_entries)}")
    lines.append("")

    for item in unique_entries:
        lines.append("------------------------------------------------------------")
        lines.append(f"Missing image: {item['filename']}")
        lines.append(f"Original src:   {item['image']}")
        lines.append(f"Page title:     {item['page_title']}")
        lines.append(f"Page file:      {item['page_rel']}")
        lines.append("")

    report.write_text("\n".join(lines), encoding="utf-8")

    print(f"⚠️ Missing image references: {len(unique_entries)}")
    print(f"⚠️ See: {report}")
else:
    print("✅ No missing image references detected")
PY
echo "🔗 Final QR GitHub REDIRECT source repair..."

python3 - "$OUTPUT_HTML" "$CONTENTS_DIR" <<'FINAL_QR_GITHUB_REDIRECT_REPAIR'
import os
import re
import sys
import html
import urllib.parse
import subprocess
from pathlib import Path
from collections import defaultdict

OUTPUT_HTML = Path(sys.argv[1])
CONTENTS_DIR = Path(sys.argv[2]).resolve()
GIT_ROOT = CONTENTS_DIR.parent

GITHUB_PREFIX = "https://github.com/RawTherapee/RawPedia/blob/master/content/"

language_codes = {
    "fr", "es", "it", "jp", "ja", "pt", "de", "ca", "ct",
    "zh", "cn", "ru", "nl", "pl", "tr"
}

def compact_key(value: str) -> str:
    value = html.unescape(value or "").strip()
    value = urllib.parse.unquote(value)
    value = value.replace("\\", "/")
    value = value.split("#", 1)[0].split("?", 1)[0]
    value = re.sub(r"/index\.html$", "", value, flags=re.I)
    value = re.sub(r"\.html$", "", value, flags=re.I)
    value = re.sub(r"\.(md|markdown|html)$", "", value, flags=re.I)
    value = value.strip("/").lower()
    return re.sub(r"[^a-z0-9]+", "", value)

def content_rel_is_probably_english(rel: str) -> bool:
    rel = rel.replace("\\", "/").strip("/")
    lower = rel.lower()
    parts = lower.split("/")

    if parts and parts[0] in language_codes:
        return False

    name = Path(lower).name
    base = re.sub(r"\.(md|markdown|html)$", "", name, flags=re.I)

    if "." in base:
        suffix = base.rsplit(".", 1)[-1]
        if suffix in language_codes:
            return False

    if re.search(
        r"(^|[-_.])(fr|es|it|jp|ja|pt|de|ca|ct|zh|cn|ru|nl|pl|tr)$",
        base,
        flags=re.I,
    ):
        return False

    return True

def git_content_rels() -> list[str]:
    try:
        result = subprocess.run(
            ["git", "-C", str(GIT_ROOT), "ls-tree", "-r", "--name-only", "HEAD", "content"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except Exception as e:
        print(f"❌ Cannot read Git tree from {GIT_ROOT}: {e}")
        sys.exit(1)

    rels = []

    for line in result.stdout.splitlines():
        line = line.strip().replace("\\", "/")

        if not line.startswith("content/"):
            continue

        rel = line[len("content/"):]

        if Path(rel).suffix.lower() not in {".md", ".markdown", ".html"}:
            continue

        if not content_rel_is_probably_english(rel):
            continue

        rels.append(rel)

    return sorted(set(rels))

_git_blob_cache = {}

def git_blob_text(content_rel: str) -> str:
    content_rel = content_rel.replace("\\", "/").strip("/")

    if content_rel in _git_blob_cache:
        return _git_blob_cache[content_rel]

    try:
        result = subprocess.run(
            ["git", "-C", str(GIT_ROOT), "show", f"HEAD:content/{content_rel}"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        text = result.stdout
    except Exception:
        text = ""

    _git_blob_cache[content_rel] = text
    return text

def plain_text(s: str) -> str:
    s = re.sub(r"<script\b.*?</script>", " ", s, flags=re.I | re.S)
    s = re.sub(r"<style\b.*?</style>", " ", s, flags=re.I | re.S)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    return re.sub(r"\s+", " ", s).strip()

def extract_frontmatter(text: str) -> str:
    if text.startswith("---"):
        m = re.match(r"(?s)^---\s*\n(.*?)\n---\s*(?:\n|$)", text)
        if m:
            return m.group(1)

    if text.startswith("+++"):
        m = re.match(r"(?s)^\+\+\+\s*\n(.*?)\n\+\+\+\s*(?:\n|$)", text)
        if m:
            return m.group(1)

    return ""

def fm_string(fm: str, field: str) -> str:
    m = re.search(
        rf"^\s*{re.escape(field)}\s*[:=]\s*['\"]?([^'\"\n#]+)['\"]?\s*$",
        fm,
        flags=re.I | re.M,
    )
    return m.group(1).strip() if m else ""

def source_title(content_rel: str) -> str:
    text = git_blob_text(content_rel)
    fm = extract_frontmatter(text)

    if not fm:
        return ""

    return fm_string(fm, "title")

def redirect_target(content_rel: str) -> str:
    text = git_blob_text(content_rel)

    if not text:
        return ""

    # Hugo/RawPedia redirect shortcodes:
    # {{< redirect "Preview_Modes" >}}
    # {{% redirect "Preview_Modes" %}}
    # {{< redirect target="Preview_Modes" >}}
    m = re.search(
        r'''\{\{[%<]\s*redirect\s+(?:target\s*=\s*|url\s*=\s*|to\s*=\s*)?["']([^"']+)["']\s*[%>]\}\}''',
        text,
        flags=re.I | re.S,
    )
    if m:
        return m.group(1).strip()

    # MediaWiki-style redirect.
    m = re.search(
        r"(?im)^\s*#?\s*redirect\s*\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]*)?\]\]",
        text,
    )
    if m:
        return m.group(1).strip()

    # Plain redirect text.
    p = plain_text(text)
    m = re.search(r"(?im)^\s*#?\s*redirect\s+(.+?)\s*$", p)
    if m:
        return m.group(1).strip()

    # Front matter redirect fields.
    fm = extract_frontmatter(text)

    if fm:
        for field in ("redirect", "redirect_to", "redirectto", "target", "to"):
            value = fm_string(fm, field)
            if value:
                return value.strip()

    return ""

def is_redirect(content_rel: str) -> bool:
    return bool(redirect_target(content_rel))

def rel_keys(content_rel: str) -> set[str]:
    rel_no_ext = re.sub(r"\.[^.]+$", "", content_rel)
    stem = Path(rel_no_ext).name
    title = source_title(content_rel)

    keys = {
        compact_key(content_rel),
        compact_key(rel_no_ext),
        compact_key(stem),
        compact_key(stem.replace("_", " ")),
        compact_key(stem.replace("-", " ")),
    }

    if title:
        keys.add(compact_key(title))
        keys.add(compact_key(title.replace(" ", "_")))
        keys.add(compact_key(title.replace(" ", "-")))

    return {k for k in keys if k}

def target_keys(target: str) -> set[str]:
    target = html.unescape(target or "").strip()
    target = urllib.parse.unquote(target)
    target = target.split("#", 1)[0].split("?", 1)[0].strip()

    variants = {
        target,
        target.replace(" ", "_"),
        target.replace(" ", "-"),
        target.replace("_", " "),
        target.replace("-", " "),
        "/" + target.strip("/"),
        target.strip("/") + "/index.html",
        target.strip("/") + ".md",
        Path(target).name,
    }

    return {compact_key(v) for v in variants if compact_key(v)}

def casing_score(content_rel: str) -> float:
    stem = Path(re.sub(r"\.[^.]+$", "", content_rel)).name
    parts = [p for p in re.split(r"[_\-\s]+", stem) if p]

    score = 0.0

    if is_redirect(content_rel):
        score -= 100000000
    else:
        score += 100000000

    # Preview_Modes beats Preview_modes.
    score += sum(1 for p in parts if p[:1].isupper()) * 10000
    score -= sum(1 for p in parts if p[:1].islower()) * 12000
    score += sum(1 for ch in stem if ch.isupper()) * 100

    # Prefer top-level source files if tied.
    score -= content_rel.count("/") * 100

    # Shorter final tie-breaker.
    score -= len(content_rel) * 0.01

    return score

all_rels = git_content_rels()

by_key = defaultdict(list)

for rel in all_rels:
    for key in rel_keys(rel):
        by_key[key].append(rel)

def best_nonredirect_for_keys(keys: set[str]) -> str:
    candidates = []

    for key in keys:
        candidates.extend(by_key.get(key, []))

    candidates = sorted(set(candidates))

    if not candidates:
        return ""

    nonredirects = [rel for rel in candidates if not is_redirect(rel)]

    if nonredirects:
        nonredirects.sort(key=lambda rel: (-casing_score(rel), rel))
        return nonredirects[0]

    candidates.sort(key=lambda rel: (-casing_score(rel), rel))
    return candidates[0]

def resolve_rel(old_rel: str) -> str:
    old_rel = urllib.parse.unquote(old_rel or "").replace("\\", "/").strip("/")

    if not old_rel:
        return ""

    # 1. Exact Git tree file: if redirect, chase its own target.
    exact = next((rel for rel in all_rels if rel == old_rel), "")

    if exact:
        target = redirect_target(exact)

        if target:
            repaired = best_nonredirect_for_keys(target_keys(target))
            if repaired:
                return repaired

        # Even if exact is nonredirect, prefer a same-key nonredirect with better casing.
        repaired = best_nonredirect_for_keys(rel_keys(exact))
        if repaired:
            return repaired

        return exact

    # 2. Not exact: resolve by filename/path keys.
    old_no_ext = re.sub(r"\.[^.]+$", "", old_rel)
    stem = Path(old_no_ext).name

    keys = {
        compact_key(old_rel),
        compact_key(old_no_ext),
        compact_key(stem),
        compact_key(stem.replace("_", " ")),
        compact_key(stem.replace("-", " ")),
    }

    candidate = best_nonredirect_for_keys(keys)

    if not candidate:
        return ""

    target = redirect_target(candidate)

    if target:
        repaired = best_nonredirect_for_keys(target_keys(target))
        if repaired:
            return repaired

    return candidate

def github_url_for_rel(content_rel: str) -> str:
    return GITHUB_PREFIX + urllib.parse.quote(content_rel, safe="/")

s = OUTPUT_HTML.read_text(encoding="utf-8", errors="replace")

github_url_re = re.compile(
    r"https://github\.com/RawTherapee/RawPedia/blob/master/content/([^\"'<>\s]+)",
    flags=re.I,
)

repairs = {}
unresolved = []

for m in github_url_re.finditer(s):
    old_url = m.group(0)
    old_rel = urllib.parse.unquote(m.group(1))

    new_rel = resolve_rel(old_rel)

    if not new_rel:
        unresolved.append(old_rel)
        continue

    new_url = github_url_for_rel(new_rel)

    if new_url != old_url:
        repairs[old_url] = new_url

if repairs:
    print(f"🔧 Final GitHub source URL repairs: {len(repairs)}")

    for old_url, new_url in sorted(repairs.items()):
        old_rel = urllib.parse.unquote(old_url.split("/content/", 1)[-1])
        new_rel = urllib.parse.unquote(new_url.split("/content/", 1)[-1])
        print(f"   {old_rel} -> {new_rel}")
        s = s.replace(old_url, new_url)
else:
    print("✅ No final GitHub source URL repairs needed")

if unresolved:
    print()
    print("⚠️ Could not resolve these GitHub content rels through Git tree:")
    for rel in sorted(set(unresolved))[:120]:
        print(f"   {rel}")

OUTPUT_HTML.write_text(s, encoding="utf-8")

# Regenerate QR SVGs from final hrefs. Do not use fragile section parsing.
s = OUTPUT_HTML.read_text(encoding="utf-8", errors="replace")

starts = [m.start() for m in re.finditer(r'<div class="article-github-qr"', s, flags=re.I)]
qr_regenerated = 0
qr_bad = []

for i, start in enumerate(starts):
    end = starts[i + 1] if i + 1 < len(starts) else len(s)
    chunk = s[start:end]

    href_m = re.search(
        r'<a\b[^>]*\bhref=["\']([^"\']*github\.com/RawTherapee/RawPedia/blob/master/content/[^"\']+)["\']',
        chunk,
        flags=re.I | re.S,
    )

    img_m = re.search(
        r'<img\b[^>]*\bsrc=["\']([^"\']*article-qrs/[^"\']+\.svg)["\']',
        chunk,
        flags=re.I | re.S,
    )

    if not href_m or not img_m:
        continue

    final_url = html.unescape(href_m.group(1)).strip()
    qr_src = html.unescape(img_m.group(1)).strip()

    if not qr_src.startswith("file://"):
        qr_bad.append(qr_src)
        continue

    qr_path = Path(urllib.parse.unquote(urllib.parse.urlsplit(qr_src).path))

    try:
        subprocess.run(
            [
                "qrencode",
                "-t", "SVG",
                "-o", str(qr_path),
                "-m", "1",
                "-s", "5",
                final_url,
            ],
            check=True,
        )
        qr_regenerated += 1
    except Exception as e:
        print(f"❌ Could not regenerate QR SVG {qr_path}: {e}")
        sys.exit(1)

print(f"✅ Article QR SVGs regenerated from final corrected URLs: {qr_regenerated}")

if qr_bad:
    print()
    print("❌ Bad QR image paths during final repair:")
    for item in qr_bad[:80]:
        print(f"   {item}")
    sys.exit(1)

# Final hard audit: every GitHub source URL in book.html must resolve to itself and not be redirect.
s = OUTPUT_HTML.read_text(encoding="utf-8", errors="replace")

bad_remaining = []
final_report_lines = []

for m in github_url_re.finditer(s):
    url = m.group(0)
    rel = urllib.parse.unquote(m.group(1))
    best = resolve_rel(rel)
    target = redirect_target(rel)

    final_report_lines.append(f"source: {rel}")
    final_report_lines.append(f"url:    {url}")

    if target:
        final_report_lines.append(f"ERROR:  redirect -> {target}")
        bad_remaining.append((rel, best or "[UNKNOWN]", target, url))

    if best and best != rel:
        final_report_lines.append(f"ERROR:  best should be {best}")
        bad_remaining.append((rel, best, target or "", url))

    final_report_lines.append("")

report = OUTPUT_HTML.parent / "article-github-source-map-final.txt"
report.write_text("\n".join(final_report_lines), encoding="utf-8")
print(f"✅ Final article GitHub source map report: {report}")

if bad_remaining:
    print()
    print("❌ Final QR GitHub URLs still point to redirect/bad source files:")
    for rel, best, target, url in bad_remaining[:120]:
        print(f"   current: {rel}")
        print(f"   best:    {best}")
        if target:
            print(f"   target:  {target}")
        print(f"   url:     {url}")
    sys.exit(1)

print("✅ Final QR GitHub URLs point to non-redirect Git source files")
FINAL_QR_GITHUB_REDIRECT_REPAIR

echo "✅ HTML book complete: $OUTPUT_HTML"
echo
echo "🔳 Checking generated article QR image paths..."

python3 - "$OUTPUT_HTML" <<'CHECK_ARTICLE_QR_PATHS'
import re
import sys
import html
import urllib.parse
from pathlib import Path

s = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

qr_srcs = [
    html.unescape(m.group(1)).strip()
    for m in re.finditer(
        r'<img\b[^>]*alt=["\']GitHub source QR code["\'][^>]*\bsrc=["\']([^"\']+)["\']',
        s,
        flags=re.I | re.S,
    )
]

# Also catch src-before-alt order.
qr_srcs += [
    html.unescape(m.group(1)).strip()
    for m in re.finditer(
        r'<img\b[^>]*\bsrc=["\']([^"\']+)["\'][^>]*alt=["\']GitHub source QR code["\']',
        s,
        flags=re.I | re.S,
    )
]

qr_srcs = sorted(set(qr_srcs))

bad = []
missing = []

for src in qr_srcs:
    if src.startswith(("http://", "https://")):
        bad.append(src)
        continue

    if not src.startswith("file://"):
        bad.append(src)
        continue

    path = urllib.parse.unquote(urllib.parse.urlsplit(src).path)

    if not Path(path).exists():
        missing.append(src)

print(f"article QR image refs: {len(qr_srcs)}")
print(f"bad/nonlocal QR refs: {len(bad)}")
print(f"missing local QR files: {len(missing)}")

if bad:
    print()
    print("❌ Article QR refs should be file:// URLs, not web URLs:")
    for item in bad[:80]:
        print(f"   {item}")
    sys.exit(1)

if missing:
    print()
    print("❌ Article QR files missing:")
    for item in missing[:80]:
        print(f"   {item}")
    sys.exit(1)

print("✅ Article QR images are local file URLs")
CHECK_ARTICLE_QR_PATHS
echo
echo "🔗 Checking internal href targets..."

python3 - "$OUTPUT_HTML" <<'CHECK_INTERNAL_HREF_TARGETS'
import re
import sys
import html
import urllib.parse
from pathlib import Path

s = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

ids = set(
    html.unescape(m.group(2)).strip()
    for m in re.finditer(r'\b(?:id|name)=(["\'])(.*?)\1', s, flags=re.I | re.S)
)

hrefs = [
    html.unescape(m.group(2)).strip()
    for m in re.finditer(r'\bhref=(["\'])(.*?)\1', s, flags=re.I | re.S)
]

internal = [
    h for h in hrefs
    if h.startswith("#") and h not in {"#", "#ZgotmplZ"}
]

missing = []

for h in internal:
    target = urllib.parse.unquote(h[1:])

    if target and target not in ids:
        missing.append(h)
        
print(f"ids/name targets: {len(ids)}")
print(f"internal hrefs: {len(internal)}")
print(f"missing internal targets: {len(missing)}")

if missing:
    print()
    print("❌ Missing internal link targets:")
    for item in sorted(set(missing))[:100]:
        print(f"   {item}")
    sys.exit(1)

print("✅ Internal href targets all exist")
CHECK_INTERNAL_HREF_TARGETS
echo
echo "🔗 Checking duplicate id/name targets..."

python3 - "$OUTPUT_HTML" <<'CHECK_DUPLICATE_TARGETS'
import re
import sys
import html
from pathlib import Path
from collections import Counter

s = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

targets = [
    html.unescape(m.group(2)).strip()
    for m in re.finditer(r'\b(?:id|name)=(["\'])(.*?)\1', s, flags=re.I | re.S)
    if html.unescape(m.group(2)).strip()
]

counts = Counter(targets)
dupes = [(target, count) for target, count in counts.items() if count > 1]

print(f"id/name targets: {len(targets)}")
print(f"duplicate targets: {len(dupes)}")

if dupes:
    print()
    print("❌ Duplicate id/name targets:")
    for target, count in sorted(dupes, key=lambda item: (-item[1], item[0]))[:120]:
        print(f"   {count}x #{target}")
    sys.exit(1)

print("✅ No duplicate id/name targets")
CHECK_DUPLICATE_TARGETS
INDEX_BODY_COUNT="$(grep -c '<div class="index-body">' "$OUTPUT_HTML" || true)"
TECH_INDEX_COUNT="$(grep -c '<section class="technical-index" id="technical-index">' "$OUTPUT_HTML" || true)"

echo "✅ Technical index section count: $TECH_INDEX_COUNT"
echo "✅ Index body count: $INDEX_BODY_COUNT"

if [[ "$TECH_INDEX_COUNT" -ne 1 || "$INDEX_BODY_COUNT" -ne 1 ]]; then
  echo "❌ Technical index was written more than once."
  echo "❌ This means the technical-index writer block is still inside another loop."
  exit 1
fi
echo "---- technical index CSS check ----"
grep -n "index-body" -A10 "$OUTPUT_HTML" || true

echo "🖼 Dereferencing MediaWiki-style image links..."

python3 - "$OUTPUT_HTML" "$SOURCE_DIR" <<'DEREFERENCE_MEDIAWIKI_IMAGES'
import os
import re
import sys
import html
import urllib.parse
from pathlib import Path

OUTPUT_HTML = Path(sys.argv[1])
SOURCE_DIR = Path(sys.argv[2]).resolve()

asset_exts = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp",
    ".tif", ".tiff", ".bmp", ".ico"
}

asset_by_name = {}

for root, dirs, files in os.walk(SOURCE_DIR):
    for name in files:
        p = (Path(root) / name).resolve()

        if p.suffix.lower() in asset_exts:
            asset_by_name.setdefault(name.lower(), p)

def find_image_by_name(name: str) -> Path | None:
    raw = html.unescape(name or "").strip()
    raw = urllib.parse.unquote(raw)
    raw = raw.replace("\\", "/")

    # Strip MediaWiki-ish prefixes.
    raw = re.sub(r"(?i)^\s*(?:image|file)\s*:\s*", "", raw).strip()

    # Strip leading local URL path wrappers if present.
    parsed = urllib.parse.urlsplit(raw)
    path = urllib.parse.unquote(parsed.path).replace("\\", "/")
    filename = Path(path).name

    if not filename:
        return None

    if Path(filename).suffix.lower() not in asset_exts:
        return None

    found = asset_by_name.get(filename.lower())

    if found and found.exists():
        return found

    return None

def image_html(filename: str, found: Path | None, original: str) -> str:
    display_name = html.escape(filename)

    if found:
        uri = found.resolve().as_uri()
        return (
            '<figure class="dereferenced-mediawiki-image">'
            f'<img src="{html.escape(uri, quote=True)}" alt="{display_name}">'
            '</figure>'
        )

    return (
        '<div class="missing-image">'
        '<strong>Missing image</strong>'
        f'<div class="missing-file">{display_name}</div>'
        f'<div class="missing-path">{html.escape(original)}</div>'
        '</div>'
    )

def replace_anchor(m):
    full = m.group(0)
    href = html.unescape(m.group(1)).strip()
    label_html = m.group(2)
    label_text = re.sub(r"<[^>]+>", "", label_html)
    label_text = html.unescape(label_text).strip()

    candidates = [label_text, href]

    for candidate in candidates:
        candidate_clean = html.unescape(candidate or "").strip()

        if not re.match(r"(?i)^(?:image|file)\s*:", candidate_clean) and not Path(urllib.parse.urlsplit(candidate_clean).path).suffix.lower() in asset_exts:
            continue

        found = find_image_by_name(candidate_clean)
        raw_name = re.sub(r"(?i)^\s*(?:image|file)\s*:\s*", "", candidate_clean).strip()
        filename = Path(urllib.parse.unquote(urllib.parse.urlsplit(raw_name).path)).name

        if filename and Path(filename).suffix.lower() in asset_exts:
            return image_html(filename, found, candidate_clean)

    return full

def replace_plain_mediawiki_image(m):
    original = m.group(0)
    raw = m.group(1)
    found = find_image_by_name(raw)
    filename = Path(urllib.parse.unquote(urllib.parse.urlsplit(raw).path)).name

    return image_html(filename, found, original)

s = OUTPUT_HTML.read_text(encoding="utf-8", errors="replace")

before_imgs = len(re.findall(r"<img\b", s, flags=re.I))
before_mediawiki = len(re.findall(r"(?i)\b(?:image|file):[^<>\s]+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)\b", s))

# Case 1:
# <a href="file:///.../Profile-filled.png">image:Profile-filled.png</a>
# <a href="/images/Profile-filled.png">Profile-filled.png</a>
s = re.sub(
    r'<a\b[^>]*\bhref=["\']([^"\']+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)(?:\?[^"\']*)?)["\'][^>]*>(.*?)</a>',
    replace_anchor,
    s,
    flags=re.I | re.S,
)

# Case 2:
# Bare text: image:Profile-filled.png
# Bare text: File:Profile-filled.png
#
# Avoid matching inside attributes by requiring the previous char not to be
# quote, slash, equals, colon, or alphanumeric.
s = re.sub(
    r'(?<!["\'=:/A-Za-z0-9])((?:image|file):[^\s<>"\']+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico))',
    replace_plain_mediawiki_image,
    s,
    flags=re.I,
)

after_imgs = len(re.findall(r"<img\b", s, flags=re.I))
after_mediawiki = len(re.findall(r"(?i)\b(?:image|file):[^<>\s]+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)\b", s))

OUTPUT_HTML.write_text(s, encoding="utf-8")

print(f"mediawiki image refs before: {before_mediawiki}")
print(f"mediawiki image refs after:  {after_mediawiki}")
print(f"img tags before: {before_imgs}")
print(f"img tags after:  {after_imgs}")
print("✅ MediaWiki-style image dereference complete")
DEREFERENCE_MEDIAWIKI_IMAGES

echo "🖼 Final image URL cleanup before PDF render..."

python3 - "$OUTPUT_HTML" "$SOURCE_DIR" "$RAWPEDIA_ONLINE_URL" <<'RAWPEDIA_IMAGE_URL_CLEANUP'
import re
import sys
import html
import urllib.parse
from pathlib import Path

OUTPUT_HTML = Path(sys.argv[1])
SOURCE_DIR = Path(sys.argv[2]).resolve()
RAWPEDIA_ONLINE_URL = sys.argv[3].rstrip("/")

asset_exts = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp",
    ".tif", ".tiff", ".bmp", ".ico"
}

def is_asset_url(value: str) -> bool:
    raw = html.unescape(value or "").strip()
    path = urllib.parse.urlsplit(raw).path
    return Path(path).suffix.lower() in asset_exts

def online_url_for_path(path: str) -> str:
    path = urllib.parse.unquote(path or "").replace("\\", "/")

    if not path:
        return path

    if not path.startswith("/"):
        path = "/" + path

    return RAWPEDIA_ONLINE_URL + path

def local_or_online(value: str) -> str:
    raw = html.unescape(value or "").strip()

    if not raw:
        return value

    if raw.startswith(("http://", "https://", "data:", "mailto:", "#")):
        return value

    parsed = urllib.parse.urlsplit(raw)
    path = urllib.parse.unquote(parsed.path).replace("\\", "/")

    if not path:
        return value

    # IMPORTANT:
    # Preserve all valid file:// URLs, even when they are outside SOURCE_DIR.
    # This protects generated QR codes in rawpedia_book/article-qrs/*.svg.
    if raw.startswith("file://"):
        local_path = Path(path)

        if local_path.exists():
            return local_path.resolve().as_uri()

        # If the file:// URL is broken, do not invent a RawPedia URL for
        # absolute local paths such as /Users/rb/rawpedia_book/article-qrs/foo.svg.
        # Leave it alone so the later preflight can report the real problem.
        if path.startswith("/"):
            return raw

        fixed = online_url_for_path(path)

        if parsed.query:
            fixed += "?" + parsed.query

        return fixed

    # Absolute local filesystem path, such as /Users/rb/rawpedia_book/article-qrs/foo.svg.
    # Keep it local if it exists.
    if path.startswith("/"):
        local_path = Path(path)

        if local_path.exists():
            return local_path.resolve().as_uri()

        # Root-relative RawPedia URL, such as /images/foo.png.
        local_candidate = SOURCE_DIR / path.lstrip("/")

        if local_candidate.exists():
            return local_candidate.resolve().as_uri()

        fixed = online_url_for_path(path)

        if parsed.query:
            fixed += "?" + parsed.query

        return fixed

    # Plain relative URL, such as foo.png or images/foo.png.
    local_candidate = SOURCE_DIR / path

    if local_candidate.exists():
        return local_candidate.resolve().as_uri()

    fixed = online_url_for_path(path)

    if parsed.query:
        fixed += "?" + parsed.query

    return fixed

def rewrite_attr(m):
    attr = m.group(1)
    quote = m.group(2)
    value = m.group(3)

    if not is_asset_url(value):
        return m.group(0)

    new_value = local_or_online(value)

    return f'{attr}={quote}{html.escape(new_value, quote=True)}{quote}'

def rewrite_srcset(m):
    attr = m.group(1)
    quote = m.group(2)
    value = m.group(3)

    out = []

    for candidate in value.split(","):
        candidate = candidate.strip()

        if not candidate:
            continue

        bits = candidate.split()
        url = bits[0]
        descriptor = " ".join(bits[1:])

        if is_asset_url(url):
            url = local_or_online(url)

        if descriptor:
            out.append(f"{url} {descriptor}")
        else:
            out.append(url)

    return f'{attr}={quote}{html.escape(", ".join(out), quote=True)}{quote}'

def rewrite_css_url(m):
    quote = m.group(1) or ""
    value = m.group(2)

    if not is_asset_url(value):
        return m.group(0)

    new_value = local_or_online(value)

    if quote:
        return f"url({quote}{new_value}{quote})"

    return f"url({new_value})"

s = OUTPUT_HTML.read_text(encoding="utf-8", errors="replace")

before_file_asset_refs = len(re.findall(r'file://[^"\'\s)<>]+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)', s, flags=re.I))
before_root = len(re.findall(
    r"""\b(?:src|href|data-src|data-original|data-lazy-src)=["']/[^"']+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)(?:\?[^"']*)?["']""",
    s,
    flags=re.I,
))

# src="/foo.png", src="foo.png", href="/images/foo.png", data-src="..."
s = re.sub(
    r"""\b(src|href|data-src|data-original|data-lazy-src)=(["'])([^"']+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)(?:\?[^"']*)?)\2""",
    rewrite_attr,
    s,
    flags=re.I | re.S,
)

# srcset="/foo.png 1x, /bar.png 2x"
s = re.sub(
    r'\b(srcset)=(["\'])(.*?)\2',
    rewrite_srcset,
    s,
    flags=re.I | re.S,
)

# CSS url("/foo.png")
s = re.sub(
    r'url\(\s*([\'"]?)([^\'")]+?\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)(?:\?[^\'")]*)?)\1\s*\)',
    rewrite_css_url,
    s,
    flags=re.I | re.S,
)

after_file_asset_refs = len(re.findall(r'file://[^"\'\s)<>]+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)', s, flags=re.I))
after_root = len(re.findall(
    r"""\b(?:src|href|data-src|data-original|data-lazy-src)=["']/[^"']+\.(?:png|jpg|jpeg|gif|svg|webp|tif|tiff|bmp|ico)(?:\?[^"']*)?["']""",
    s,
    flags=re.I,
))

OUTPUT_HTML.write_text(s, encoding="utf-8")

print(f"Before cleanup: local file asset refs={before_file_asset_refs}, root-relative asset attrs={before_root}")
print(f"After cleanup:  local file asset refs={after_file_asset_refs}, root-relative asset attrs={after_root}")

print("✅ Final image URL cleanup complete")
RAWPEDIA_IMAGE_URL_CLEANUP
echo "🔧 Preparing final image cleanup before PDF render..."

if ! command -v weasyprint >/dev/null 2>&1; then
  echo "❌ weasyprint not found."
  echo "Activate your venv first:"
  echo "source myvenv/bin/activate"
  exit 1
fi
echo
echo "🖼 Image resolver..."

python3 - "$OUTPUT_HTML" "$SOURCE_DIR" "$RAWPEDIA_ONLINE_URL" <<'IMAGE_RESOLVER'
import os
import re
import sys
import html
import urllib.parse

from pathlib import Path

OUTPUT_HTML = Path(sys.argv[1])
SOURCE_DIR = Path(sys.argv[2]).resolve()
RAWPEDIA_ONLINE_URL = sys.argv[3].rstrip("/")

asset_exts = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp",
    ".tif", ".tiff", ".bmp", ".ico"
}

asset_by_name = {}
asset_by_rel = {}

for root, dirs, files in os.walk(SOURCE_DIR):
    for name in files:
        p = (Path(root) / name).resolve()

        if p.suffix.lower() not in asset_exts:
            continue

        rel = str(p.relative_to(SOURCE_DIR)).replace("\\", "/").lower()
        asset_by_rel.setdefault(rel, p)
        asset_by_name.setdefault(name.lower(), p)

print(f"asset_by_name: {len(asset_by_name)}")
print(f"asset_by_rel: {len(asset_by_rel)}")

def is_asset_value(value: str) -> bool:
    value = html.unescape(value or "").strip()
    path = urllib.parse.urlsplit(value).path
    return Path(path).suffix.lower() in asset_exts

def online_for(value: str) -> str:
    raw = html.unescape(value or "").strip()
    path = urllib.parse.urlsplit(raw).path
    filename = Path(urllib.parse.unquote(path)).name

    if filename:
        return f"{RAWPEDIA_ONLINE_URL}/images/{urllib.parse.quote(filename)}"

    return raw

def find_asset(value: str) -> Path | None:
    raw = html.unescape(value or "").strip()

    if not raw:
        return None

    parsed = urllib.parse.urlsplit(raw)
    path = urllib.parse.unquote(parsed.path).replace("\\", "/").strip()

    if not path:
        return None

    candidates = []

    p = Path(path)

    if raw.startswith("file://") and p.exists():
        candidates.append(p)

    if p.is_absolute() and p.exists():
        candidates.append(p)

    if path.startswith("/"):
        candidates.append(SOURCE_DIR / path.lstrip("/"))
    else:
        candidates.append(SOURCE_DIR / path)

    rel_key = path.lstrip("/").lower()

    if rel_key in asset_by_rel:
        candidates.append(asset_by_rel[rel_key])

    if rel_key.startswith("images/"):
        short_key = rel_key.removeprefix("images/")
        if short_key in asset_by_rel:
            candidates.append(asset_by_rel[short_key])
    else:
        images_key = f"images/{rel_key}"
        if images_key in asset_by_rel:
            candidates.append(asset_by_rel[images_key])

    # Critical fallback: basename lookup.
    base = Path(path).name.lower()
    if base in asset_by_name:
        candidates.append(asset_by_name[base])

    for c in candidates:
        try:
            c = Path(c).resolve()
        except Exception:
            continue

        if c.exists() and c.suffix.lower() in asset_exts:
            return c

    return None

def make_missing_svg(raw: str, filename: str) -> Path:
    placeholder_dir = OUTPUT_HTML.parent / "online-image-fallbacks"
    placeholder_dir.mkdir(parents=True, exist_ok=True)

    safe_stem = Path(filename or "missing-image").stem or "missing-image"
    safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", safe_stem).strip("-") or "missing-image"

    placeholder_path = placeholder_dir / f"{safe_stem}-missing.svg"

    placeholder_path.write_text(
        f'''<svg xmlns="http://www.w3.org/2000/svg" width="900" height="320" viewBox="0 0 900 320">
  <rect width="900" height="320" fill="#f4f4f4"/>
  <rect x="12" y="12" width="876" height="296" fill="none" stroke="#999" stroke-width="4" stroke-dasharray="16 10"/>
  <text x="450" y="120" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="34" fill="#800">Missing image</text>
  <text x="450" y="175" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="23" fill="#555">{html.escape(filename or "unknown")}</text>
  <text x="450" y="225" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="16" fill="#777">{html.escape(raw[:120])}</text>
</svg>
''',
        encoding="utf-8",
    )

    return placeholder_path.resolve()


def resolve_url(value: str) -> str:
    raw = html.unescape(value or "").strip()

    if not raw:
        return raw

    if raw.startswith(("data:", "mailto:", "#")):
        return raw

    if raw.startswith(("http://", "https://")):
        found = find_asset(raw)

        if found:
            return found.as_uri()

        parsed = urllib.parse.urlsplit(raw)
        filename = Path(urllib.parse.unquote(parsed.path)).name or "missing-image"

        print(f"⚠️ Online image not found locally; using local placeholder: {raw}")
        return make_missing_svg(raw, filename).as_uri()

    # Preserve valid local file URLs, including generated article QR SVGs.
    if raw.startswith("file://"):
        parsed = urllib.parse.urlsplit(raw)
        path = urllib.parse.unquote(parsed.path)

        if Path(path).exists():
            return Path(path).resolve().as_uri()

        filename = Path(path).name or "missing-image"
        print(f"⚠️ Broken file:// image; using local placeholder: {raw}")
        return make_missing_svg(raw, filename).as_uri()

    # Preserve valid absolute local filesystem paths.
    if raw.startswith("/"):
        path = Path(raw)

        if path.exists():
            return path.resolve().as_uri()

    found = find_asset(raw)

    if found:
        return found.as_uri()

    online = online_for(raw)
    filename = Path(urllib.parse.unquote(urllib.parse.urlsplit(online).path)).name or "missing-image"

    print(f"⚠️ Image not found locally; using local placeholder: {raw}")
    return make_missing_svg(raw, filename).as_uri()

def rewrite_srcset_value(value: str) -> str:
    parts = []

    for candidate in value.split(","):
        candidate = candidate.strip()

        if not candidate:
            continue

        bits = candidate.split()
        url = bits[0]
        descriptor = " ".join(bits[1:])

        if is_asset_value(url):
            url = resolve_url(url)

        if descriptor:
            parts.append(f"{url} {descriptor}")
        else:
            parts.append(url)

    return ", ".join(parts)

def rewrite_img_tag(m):
    tag = m.group(0)

    def replace_quoted_attr(attr_name, value_rewriter):
        nonlocal tag

        def repl(am):
            quote = am.group(1)
            value = am.group(2)
            new_value = value_rewriter(value)
            return f'{attr_name}={quote}{html.escape(new_value, quote=True)}{quote}'

        tag = re.sub(
            rf'\b{re.escape(attr_name)}\s*=\s*(["\'])(.*?)\1',
            repl,
            tag,
            flags=re.I | re.S,
        )

    def replace_unquoted_src():
        nonlocal tag

        def repl(am):
            value = am.group(1)
            new_value = resolve_url(value) if is_asset_value(value) else value
            return f'src="{html.escape(new_value, quote=True)}"'

        tag = re.sub(
            r'\bsrc\s*=\s*([^"\'\s>]+)',
            repl,
            tag,
            flags=re.I | re.S,
        )

    # Rewrite quoted attrs.
    for attr in ("src", "data-src", "data-original", "data-lazy-src"):
        replace_quoted_attr(
            attr,
            lambda v: resolve_url(v) if is_asset_value(v) else v,
        )

    replace_quoted_attr("srcset", rewrite_srcset_value)

    # Rewrite unquoted src=foo.jpg.
    replace_unquoted_src()

    # If no src but has data-src/data-original/data-lazy-src, promote it to src.
    if not re.search(r'\bsrc\s*=', tag, flags=re.I):
        dm = re.search(
            r"""\b(?:data-src|data-original|data-lazy-src)\s*=\s*(["'])(.*?)\1""",
            tag,
            flags=re.I | re.S,
        )

        if dm and is_asset_value(dm.group(2)):
            src = resolve_url(dm.group(2))
            tag = tag[:-1] + f' src="{html.escape(src, quote=True)}">'

    return tag

s = OUTPUT_HTML.read_text(encoding="utf-8", errors="replace")

before_imgs = len(re.findall(r"<img\b", s, flags=re.I))
before_src_file = len(re.findall(r'\bsrc\s*=\s*["\']file://', s, flags=re.I))
before_src_http = len(re.findall(r'\bsrc\s*=\s*["\']https?://', s, flags=re.I))

s = re.sub(r"<img\b[^>]*>", rewrite_img_tag, s, flags=re.I | re.S)

after_imgs = len(re.findall(r"<img\b", s, flags=re.I))
after_src_file = len(re.findall(r'\bsrc\s*=\s*["\']file://', s, flags=re.I))
after_src_http = len(re.findall(r'\bsrc\s*=\s*["\']https?://', s, flags=re.I))

OUTPUT_HTML.write_text(s, encoding="utf-8")

print(f"img tags before: {before_imgs}")
print(f"img tags after:  {after_imgs}")
print(f"src file before: {before_src_file}")
print(f"src file after:  {after_src_file}")
print(f"src http before: {before_src_http}")
print(f"src http after:  {after_src_http}")
print("✅ Image resolver complete")
IMAGE_RESOLVER

echo
echo "🔳 Re-checking generated article QR image paths after cleanup..."

python3 - "$OUTPUT_HTML" <<'CHECK_ARTICLE_QR_PATHS_AFTER_CLEANUP'
import re
import sys
import html
import urllib.parse
from pathlib import Path

s = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

qr_srcs = []

for tag in re.findall(r'<img\b[^>]*>', s, flags=re.I | re.S):
    if "GitHub source QR code" not in html.unescape(tag):
        continue

    m = re.search(r'\bsrc=["\']([^"\']+)["\']', tag, flags=re.I | re.S)

    if m:
        qr_srcs.append(html.unescape(m.group(1)).strip())

qr_srcs = sorted(set(qr_srcs))

bad = []
missing = []

for src in qr_srcs:
    if src.startswith(("http://", "https://")):
        bad.append(src)
        continue

    if not src.startswith("file://"):
        bad.append(src)
        continue

    path = urllib.parse.unquote(urllib.parse.urlsplit(src).path)

    if not Path(path).exists():
        missing.append(src)

print(f"article QR image refs after cleanup: {len(qr_srcs)}")
print(f"bad/nonlocal QR refs after cleanup: {len(bad)}")
print(f"missing local QR files after cleanup: {len(missing)}")

if bad:
    print()
    print("❌ Article QR refs were changed away from local file:// URLs:")
    for item in bad[:120]:
        print(f"   {item}")
    sys.exit(1)

if missing:
    print()
    print("❌ Article QR files missing after cleanup:")
    for item in missing[:120]:
        print(f"   {item}")
    sys.exit(1)

print("✅ Article QR images are still local file URLs after cleanup")
CHECK_ARTICLE_QR_PATHS_AFTER_CLEANUP

echo
echo "🔎 Final image preflight before WeasyPrint..."

python3 - "$OUTPUT_HTML" <<'FINAL_IMAGE_PREFLIGHT'
import re
import sys
import html
import urllib.parse
from pathlib import Path

s = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

imgs = re.findall(r"<img\b[^>]*>", s, flags=re.I | re.S)

bad_src = []
missing_local = []

src_count = 0
file_count = 0
http_count = 0
data_count = 0

for tag in imgs:
    m = re.search(r'\bsrc\s*=\s*(["\'])(.*?)\1', tag, flags=re.I | re.S)

    if not m:
        bad_src.append("[NO SRC] " + re.sub(r"\s+", " ", tag)[:180])
        continue

    src_count += 1
    src = html.unescape(m.group(2)).strip()

    if src.startswith("file://"):
        file_count += 1
        path = urllib.parse.unquote(urllib.parse.urlsplit(src).path)
        if not Path(path).exists():
            missing_local.append(src)
    elif src.startswith(("http://", "https://")):
        http_count += 1
        bad_src.append(src)
    elif src.startswith("data:"):
        data_count += 1
    else:
        bad_src.append(src)

print(f"img tags: {len(imgs)}")
print(f"img src attrs: {src_count}")
print(f"file src: {file_count}")
print(f"http src: {http_count}")
print(f"data src: {data_count}")
print(f"bad/nonlocal/http/no src: {len(bad_src)}")
print(f"missing local file src: {len(missing_local)}")

if bad_src:
    print()
    print("❌ Bad or online image src values remain:")
    for item in sorted(set(bad_src))[:80]:
        print(f"   {item}")
    sys.exit(1)

if missing_local:
    print()
    print("❌ Local file image URLs still point to missing files:")
    for item in sorted(set(missing_local))[:80]:
        print(f"   {item}")
    sys.exit(1)

if file_count + http_count + data_count < 50:
    print()
    print("❌ Too few usable image src values. Refusing to render image-less PDF.")
    sys.exit(1)

print("✅ Final image preflight passed")
FINAL_IMAGE_PREFLIGHT

echo
echo "---- href refs in generated book.html ----"

python3 - "$OUTPUT_HTML" <<'HREF_REF_REPORT'
import re
import sys
import html
from pathlib import Path

s = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

hrefs = [
    html.unescape(m.group(2)).strip()
    for m in re.finditer(r'\bhref=(["\'])(.*?)\1', s, flags=re.I | re.S)
]

internal = [h for h in hrefs if h.startswith("#")]
file_refs = [h for h in hrefs if h.startswith("file://")]
old_rawpedia = [h for h in hrefs if "rawpedia.rawtherapee.com" in h]
rawpixls = [h for h in hrefs if "rawpedia.rawpixls.us" in h]
pixls = [h for h in hrefs if "rawpedia.pixls.us" in h]
download_exts = {
    ".pp3", ".pdf", ".zip", ".7z", ".gz", ".bz2", ".xz",
    ".dcp", ".icc", ".icm", ".txt", ".json",
    ".exe", ".dmg", ".appimage", ".cr3", ".cr2", ".nef", ".arw", ".dng"
}

relative = [
    h for h in hrefs
    if h
    and not h.startswith(("#", "file://", "http://", "https://", "mailto:", "tel:", "data:"))
]

relative_manual_links = [
    h for h in relative
    if Path(h.split("#", 1)[0].split("?", 1)[0]).suffix.lower() not in download_exts
]

print(f"href attrs: {len(hrefs)}")
print(f"internal # refs: {len(internal)}")
print(f"file:// href refs: {len(file_refs)}")
print(f"old rawpedia.rawtherapee.com refs: {len(old_rawpedia)}")
print(f"rawpedia.rawpixls.us refs: {len(rawpixls)}")
print(f"rawpedia.pixls.us refs: {len(pixls)}")
print(f"relative href refs: {len(relative)}")
print(f"relative manual-page href refs: {len(relative_manual_links)}")

if file_refs:
    print()
    print("sample file:// href refs:")
    for h in file_refs[:40]:
        print(f"  {h}")

if relative:
    print()
    print("sample relative href refs:")
    for h in relative[:40]:
        print(f"  {h}")

if relative_manual_links:
    print()
    print("sample relative manual-page href refs:")
    for h in relative_manual_links[:40]:
        print(f"  {h}")

if old_rawpedia:
    print()
    print("sample old RawPedia refs:")
    for h in old_rawpedia[:40]:
        print(f"  {h}")

if relative_manual_links:
    print()
    print("❌ Relative manual-page href refs remain. These will not work as internal PDF jumps.")
    print("❌ Fix link rewriting before rendering.")
    for h in relative_manual_links[:80]:
        print(f"  {h}")
    sys.exit(1)
    
HREF_REF_REPORT

echo
echo "🔗 Scrubbing file:/// HTML hyperlinks back to internal anchors..."

python3 - "$OUTPUT_HTML" <<'SCRUB_FILE_HTML_HREFS'
import re
import sys
import html
import urllib.parse
from pathlib import Path

html_path = Path(sys.argv[1]).resolve()
html_dir = html_path.parent

s = html_path.read_text(encoding="utf-8", errors="replace")

def repl(m):
    quote = m.group(1)
    href_raw = html.unescape(m.group(2)).strip()

    if not href_raw.startswith("file://"):
        return m.group(0)

    parsed = urllib.parse.urlsplit(href_raw)
    local_path = Path(urllib.parse.unquote(parsed.path))

    # Convert file:///.../book.html#target back to #target.
    try:
        same_file = local_path.resolve() == html_path
    except Exception:
        same_file = False

    if same_file and parsed.fragment:
        return f'href={quote}#{html.escape(parsed.fragment, quote=True)}{quote}'

    # Convert file:///.../some-generated-page/index.html to an internal
    # manual link if the fragment already points at a manual anchor.
    if parsed.fragment.startswith(("page-", "contents", "technical-index", "toc-")):
        return f'href={quote}#{html.escape(parsed.fragment, quote=True)}{quote}'

    return m.group(0)

s2 = re.sub(
    r'\bhref=(["\'])(.*?)\1',
    repl,
    s,
    flags=re.I | re.S,
)

html_path.write_text(s2, encoding="utf-8")

before = len(re.findall(r'\bhref=["\']file://', s, flags=re.I))
after = len(re.findall(r'\bhref=["\']file://', s2, flags=re.I))

print(f"file:// hrefs before: {before}")
print(f"file:// hrefs after:  {after}")

if after:
    print("⚠️ Some file:// hrefs remain. These may be legitimate local file/download links.")
SCRUB_FILE_HTML_HREFS

echo
echo "🔗 Checking for bad file:/// text hyperlinks..."

python3 - "$OUTPUT_HTML" <<'CHECK_FILE_HREFS'
import re
import sys
import html
from pathlib import Path

s = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")

bad = []

for m in re.finditer(r'<a\b[^>]*\bhref=(["\'])(.*?)\1[^>]*>', s, flags=re.I | re.S):
    tag = m.group(0)
    href = html.unescape(m.group(2)).strip()

    if not href.startswith("file://"):
        continue

    # Image src=file:// is fine. Anchor href=file:// is what creates bad PDF links.
    bad.append(href)

print(f"file:// anchor hrefs: {len(bad)}")

if bad:
    print()
    print("❌ file:// anchor hrefs remain:")
    for h in sorted(set(bad))[:120]:
        print(f"   {h}")
    sys.exit(1)

print("✅ No file:// anchor hrefs remain")
CHECK_FILE_HREFS

echo "📄 Rendering PDF..."

BOOK_BASE_URL="$(
python3 - "$OUTPUT_HTML" <<'PY'
import sys
from pathlib import Path
print(Path(sys.argv[1]).resolve().parent.as_uri() + "/")
PY
)"

echo "✅ PDF base URL: $BOOK_BASE_URL"

weasyprint \
  --base-url "$BOOK_BASE_URL" \
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

    if isinstance(obj, dict):
        if "/A" in obj:
            action = obj["/A"]

            if isinstance(action, dict):
                subtype = action.get("/S")

                if subtype == "/URI":
                    uri_count += 1
                    uri = action.get("/URI", "")
                    if len(samples) < 20:
                        samples.append(str(uri))
                elif subtype == "/GoTo":
                    goto_count += 1
                else:
                    other_count += 1

        for value in obj.values():
            walk(value)

    elif isinstance(obj, list):
        for value in obj:
            walk(value)

walk(data)

if goto_count or uri_count or other_count:
    print(f"PDF GoTo internal links: {goto_count}")
    print(f"PDF URI external links:  {uri_count}")
    print(f"PDF other link actions:  {other_count}")

bad_fragment_uris = [
    s for s in samples
    if "#page-" in s or "#contents" in s or "#technical-index" in s
]

if bad_fragment_uris:
    print()
    print("❌ Internal-looking links were emitted as external URI links:")
    for s in bad_fragment_uris[:20]:
        print(f"   {s}")
    sys.exit(1)

print("✅ PDF link-action check complete")
CHECK_PDF_LINK_ACTIONS

echo
echo
echo "📄 Creating final publisher-ready PDF inside the same WeasyPrint document..."

if ! command -v qpdf >/dev/null 2>&1; then
  echo "❌ qpdf not found; cannot calculate publisher padding."
  echo "   Install with: brew install qpdf"
  exit 1
fi

PAGE_COUNT="$(qpdf --show-npages "$OUTPUT_PDF")"

# We are always appending two final pages:
#   1. blank page with 1 inch rtdata icon
#   2. final page with 5 inch rtdata icon
FINAL_PAGE_COUNT=2

# Padding must happen BEFORE those final pages.
# Compute padding so: original + padding + 2 final pages is divisible by 4.
REMAINDER=$(( (PAGE_COUNT + FINAL_PAGE_COUNT) % 4 ))

if (( REMAINDER == 0 )); then
  PAD_NEEDED=0
else
  PAD_NEEDED=$(( 4 - REMAINDER ))
fi

EXPECTED_FINAL_TOTAL=$(( PAGE_COUNT + PAD_NEEDED + FINAL_PAGE_COUNT ))

echo "📄 Original page count: $PAGE_COUNT"
echo "📄 Reserved final icon pages: $FINAL_PAGE_COUNT"
echo "📄 Padding blankies needed before final pages: $PAD_NEEDED"
echo "📄 Expected final page count: $EXPECTED_FINAL_TOTAL"

echo "📄 Injecting final publisher pages into main HTML..."

python3 - "$OUTPUT_HTML" "$PAD_NEEDED" "$RT_HEADER_PNG" <<'INJECT_FINAL_PAGES'
import sys
from pathlib import Path

html_path = Path(sys.argv[1])
pad_needed = int(sys.argv[2])
icon_uri = Path(sys.argv[3]).resolve().as_uri()

s = html_path.read_text(encoding="utf-8", errors="replace")

marker = '<!-- RAWPEDIA_FINAL_PUBLISHER_PAGES -->'

# Remove old injected final pages if this script is re-run.
if marker in s:
    s = s.split(marker, 1)[0].rstrip() + "\n</body>\n</html>\n"

sections = []
sections.append(marker)

for i in range(pad_needed):
    sections.append(f"""
<section class="publisher-blank-page">
  <img src="{icon_uri}" alt="">
</section>
""")

sections.append(f"""
<section class="publisher-final-blank-page">
  <img src="{icon_uri}" alt="">
</section>

<section class="publisher-final-icon-page">
  <img src="{icon_uri}" alt="RawTherapee icon">
</section>
""")

injected = "\n".join(sections)

extra_css = """
<style id="publisher-final-pages-style">
@page publisherfinal {
  size: 8.125in 10.25in;
  margin: 0;

  @top-left { content: ""; }
  @top-center { content: ""; }
  @top-right { content: ""; }
  @bottom-left { content: ""; }
  @bottom-center { content: ""; }
  @bottom-right { content: ""; }
}

.publisher-blank-page,
.publisher-final-blank-page,
.publisher-final-icon-page {
  page: publisherfinal;
  break-before: page;
  break-after: page;
  width: 8.125in;
  height: 10.25in;
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  background: white;
  display: flex;
  align-items: center;
  justify-content: center;
  string-set: article "";
}

.publisher-blank-page img,
.publisher-final-blank-page img {
  width: 1in;
  height: 1in;
  object-fit: contain;
  background: transparent;
}

.publisher-final-icon-page img {
  width: 5in;
  height: 5in;
  object-fit: contain;
  background: transparent;
}
</style>
"""

if "publisher-final-pages-style" not in s:
    s = s.replace("</head>", extra_css + "\n</head>")

s = s.replace("</body>", injected + "\n</body>")

html_path.write_text(s, encoding="utf-8")
print(f"✅ Injected {pad_needed} padding page(s) plus 2 final logo pages")
INJECT_FINAL_PAGES

echo "📄 Rendering final PDF in one WeasyPrint pass so internal links survive..."

BOOK_BASE_URL="$(
python3 - "$OUTPUT_HTML" <<'PY'
import sys
from pathlib import Path
print(Path(sys.argv[1]).resolve().parent.as_uri() + "/")
PY
)"

echo "✅ PDF base URL: $BOOK_BASE_URL"

weasyprint \
  --base-url "$BOOK_BASE_URL" \
  "$OUTPUT_HTML" \
  "$OUTPUT_PDF"
  
FINAL_PAGE_TOTAL="$(qpdf --show-npages "$OUTPUT_PDF")"

echo
echo "🔗 Checking final PDF for bad file:/// link annotations..."

python3 - "$OUTPUT_PDF" <<'CHECK_FINAL_PDF_FILE_LINKS'
import sys
import subprocess
import re
from pathlib import Path

pdf = Path(sys.argv[1])

try:
    result = subprocess.run(
        [
            "qpdf",
            "--qdf",
            "--object-streams=disable",
            str(pdf),
            "-",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
except FileNotFoundError:
    print("⚠️ qpdf not found; skipping final PDF file-link check.")
    sys.exit(0)
except subprocess.CalledProcessError as e:
    print("⚠️ qpdf could not inspect final PDF links; skipping.")
    print(e.stderr.decode("utf-8", errors="replace")[:1000])
    sys.exit(0)

text = result.stdout.decode("latin-1", errors="replace")

file_uris = sorted(set(re.findall(r"/URI\s*\((file://[^)]*)\)", text)))

print(f"PDF file:// URI links: {len(file_uris)}")

if file_uris:
    print()
    print("❌ Final PDF still contains file:// hyperlink annotations:")
    for item in file_uris[:120]:
        print(f"   {item}")
    sys.exit(1)

print("✅ Final PDF contains no file:// hyperlink annotations")
CHECK_FINAL_PDF_FILE_LINKS

echo "✅ Final publisher-ready PDF complete: $OUTPUT_PDF"
echo "✅ Final page count: $FINAL_PAGE_TOTAL"

if [[ "$FINAL_PAGE_TOTAL" != "$EXPECTED_FINAL_TOTAL" ]]; then
  echo "❌ Final PDF page count mismatch."
  echo "   original:  $PAGE_COUNT"
  echo "   padding:   $PAD_NEEDED"
  echo "   final:     $FINAL_PAGE_COUNT"
  echo "   expected:  $EXPECTED_FINAL_TOTAL"
  echo "   actual:    $FINAL_PAGE_TOTAL"
  exit 1
fi

if (( FINAL_PAGE_TOTAL % 4 != 0 )); then
  echo "❌ Final PDF page count is not divisible by 4."
  exit 1
fi

echo "✅ Final PDF includes original + padding + final logo pages."
echo "✅ Final PDF page count is divisible by 4."

if [[ -f "$WORK_DIR/missing-images.txt" ]]; then
  echo "⚠️ Some images were still missing."
  echo "   See: $WORK_DIR/missing-images.txt"
fi
