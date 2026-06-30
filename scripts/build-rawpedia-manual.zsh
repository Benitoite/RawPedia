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

def term_id(term: str) -> str:
    return "index-" + re.sub(r"[^A-Za-z0-9]+", "-", term).strip("-").lower()

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

    if article_toc:
        content = article_toc + "\n" + content

    content = strip_empty_leading_blocks(content)

    if not has_meaningful_content(content, title):
        continue

    order, section = page_kind(title, rel)

    infos.append({
        "path": page,
        "rel": rel,
        "id": page_id,
        "title": title,
        "section": section,
        "section_id": section_toc_id(section),
        "section_order": order,
        "content": content,
    })

infos.sort(key=page_sort_key)

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
print(f"✅ Technical index terms with hits: {len(technical_index)}")
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
    print(f"✅ Technical index report: {report}")

contributors_display = ", ".join(contributors_sorted)

if not contributors_display:
    contributors_display = "No contributor metadata was found in ~/RawPedia/content."

authors_display = ", ".join(authors_from_file)

if not authors_display:
    authors_display = "No AUTHORS.txt data was found at ~/repo-rt/AUTHORS.txt."

license_html = html.escape(license_text)

with OUTPUT_HTML.open("w", encoding="utf-8") as out:
    out.write(f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>RawTherapee Manual</title>
<style>
@page {{
  size: Letter;
  margin: 0.72in 0.5in 0.72in 0.5in;

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
    content: string(article);
    font-family: Helvetica, Arial, sans-serif;
    font-size: 7.5pt;
    color: #666;
  }}

  @bottom-right {{
    content: "";
  }}
}}

@page cover {{
  margin: 0.6in;

  @top-left {{ content: ""; }}
  @top-center {{ content: ""; }}
  @top-right {{ content: ""; }}
  @bottom-left {{ content: ""; }}
  @bottom-center {{ content: ""; }}
  @bottom-right {{ content: ""; }}
}}

@page frontmatter {{
  margin: 0.72in 0.65in 0.72in 0.65in;

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

@page tocpage {{
  margin: 0.62in 0.55in 0.68in 0.55in;

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

@page indexpage {{
  margin: 0.62in 0.55in 0.68in 0.55in;

  @top-left {{
    content: element(bookHeader);
    width: 2.1in;
  }}

  @top-center {{
    content: "Technical Index";
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
    content: "Technical Index";
    font-family: Helvetica, Arial, sans-serif;
    font-size: 7.5pt;
    color: #666;
  }}

  @bottom-right {{
    content: "";
  }}
}}

html, body {{
  font-family: Georgia, "Times New Roman", serif;
  font-size: 9.15pt;
  line-height: 1.22;
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

.cover {{
  page: cover;
  height: 9.4in;
  display: flex;
  flex-direction: column;
  justify-content: center;
  text-align: center;
  break-after: page;
}}

.cover-icon-frame {{
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: #1d1d1d;
  border-radius: 0.45in;
  padding: 0.26in;
  margin: 0 auto 0.45in auto;
  border: 0.5pt solid #333;
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

.cover h1 {{
  font-size: 36pt;
  line-height: 1.02;
  margin: 0 0 0.15in 0;
  letter-spacing: -0.02em;
}}

.cover-date {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 22pt;
  line-height: 1.05;
  color: #444;
  margin: 0 0 0.18in 0;
}}

.cover .subtitle {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 15pt;
  color: #555;
  margin-top: 0.06in;
}}

.cover .edition {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 9.5pt;
  color: #777;
  margin-top: 0.35in;
}}

.git-version-box {{
  font-family: Helvetica, Arial, sans-serif;
  color: #111;
  border: 1.1pt solid #333;
  background: #f3f3f3;
  padding: 0.11in 0.15in;
  text-align: left;
}}

.git-version-box div {{
  margin: 0.035in 0;
}}

.cover-git-version {{
  font-size: 13.5pt;
  line-height: 1.15;
  font-weight: bold;
  margin: 0.36in auto 0 auto;
  width: 5.6in;
}}

.copyright-page {{
  page: frontmatter;
  break-after: page;
  font-size: 9.2pt;
  line-height: 1.35;
  string-set: article "Copyright";
}}

.copyright-inner {{
  margin-top: 1.35in;
}}

.contributor-list,
.authors-list {{
  font-size: 7.2pt;
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

.license-source {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 5.5pt;
  color: #666;
  margin-bottom: 0.055in;
  overflow-wrap: anywhere;
}}

.license-text {{
  column-count: 3;
  column-gap: 0.138in;
  column-rule: 0.25pt solid #ddd;
  white-space: pre-wrap;
  font-family: Menlo, Consolas, monospace;
  font-size: 4pt;
  line-height: 1.075;
  overflow-wrap: normal;
  word-break: normal;
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
  height: 8.2in;
  display: flex;
  flex-direction: column;
  justify-content: center;
  string-set: article content();
}}

.part-page .part-kicker {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 9pt;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #777;
  margin-bottom: 0.14in;
}}

.part-page h1 {{
  font-size: 27pt;
  line-height: 1.05;
  margin: 0;
}}

.article {{
  break-before: page;
  string-set: article attr(data-title);
}}

.article h1.article-title {{
  font-size: 17pt;
  line-height: 1.05;
  margin: 0 0 0.15in 0;
  padding-bottom: 0.05in;
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
  font-size: 14pt;
  margin: 0.5em 0 0.22em 0;
}}

.article-body h2 {{
  font-size: 12pt;
  margin: 0.48em 0 0.18em 0;
}}

.article-body h3 {{
  font-size: 10.5pt;
  margin: 0.38em 0 0.14em 0;
}}

.article-body h4 {{
  font-size: 9.6pt;
  margin: 0.3em 0 0.1em 0;
}}

p {{
  margin: 0 0 0.32em 0;
}}

ul, ol {{
  margin-top: 0.12em;
  margin-bottom: 0.34em;
  padding-left: 1.15em;
}}

li {{
  margin: 0 0 0.12em 0;
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
  font-size: 7.6pt;
}}

td, th {{
  border: 0.3pt solid #ccc;
  padding: 2px 3px;
  vertical-align: top;
}}

pre {{
  background: #f5f5f5;
  border: 0.3pt solid #ddd;
  padding: 0.4em;
  white-space: pre-wrap;
  overflow-wrap: break-word;
  font-size: 6.9pt;
  line-height: 1.09;
}}

code {{
  font-family: Menlo, Consolas, monospace;
  font-size: 7.2pt;
  background: #eee;
  padding: 0 2px;
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
  string-set: article "Technical Index";
}}

.technical-index h1 {{
  font-size: 24pt;
  margin: 0 0 0.25in 0;
}}

.index-note {{
  font-family: Helvetica, Arial, sans-serif;
  font-size: 8pt;
  color: #666;
  margin: 0 0 0.18in 0;
}}

.index-body {{
  column-count: 2;
  column-gap: 1.2em;
  column-rule: 0.25pt solid #ccc;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 8.2pt;
  line-height: 1.22;
}}

.index-letter {{
  break-after: avoid;
  font-family: Helvetica, Arial, sans-serif;
  font-size: 12pt;
  font-weight: bold;
  margin: 0.16in 0 0.055in 0;
  border-bottom: 0.4pt solid #aaa;
}}

.index-entry {{
  break-inside: avoid;
  margin: 0 0 0.04in 0;
}}

.index-term {{
  font-weight: bold;
}}

.index-pages {{
  margin-left: 0.08in;
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
<h1>RawTherapee Manual</h1>
<div class="cover-date">{html.escape(BUILD_DATE)}</div>
<div class="subtitle">A book-style local reference for RawTherapee</div>
<div class="edition">Compiled from a local RAWPedia mirror</div>
<div class="git-version-box cover-git-version">
  <div>{html.escape(RT_GIT_VERSION)}</div>
  <div>{html.escape(RAWPEDIA_GIT_VERSION)}</div>
</div>
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

    out.write("""
<section class="half-title">
<h1>RawTherapee Manual</h1>
<p>A local manual generated from RAWPedia.</p>
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
<div class="license-source">{html.escape(license_source or "No local license file found.")}</div>
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
<h1>Preface</h1>
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
</div>
</section>
""")

    current_section = None
    part_num = 0

    for info in infos:
        section = info["section"]
        section_id = info["section_id"]

        if section != current_section:
            current_section = section
            part_num += 1

            out.write(f"""
<div class="running-section-link">
  <a href="#{html.escape(section_id)}">{html.escape(section)}</a>
</div>
<section class="part-page">
<div class="part-kicker">Section {part_num}</div>
<h1>{html.escape(section)}</h1>
</section>
""")
        else:
            out.write(f"""
<div class="running-section-link">
  <a href="#{html.escape(section_id)}">{html.escape(section)}</a>
</div>
""")

        print(f"  ➜ [{section}] {info['title']}")

        out.write(f"""
<section class="article" data-section="{html.escape(section)}" data-title="{html.escape(info["title"])}">
<div class="section-label">{html.escape(section)}</div>
<h1 class="article-title" id="page-{html.escape(info["id"])}">{html.escape(info["title"])}</h1>
<div class="article-body">
{info["content"]}
</div>
</section>
""")

    out.write("""
<section class="technical-index" id="technical-index">
<h1>Technical Index</h1>
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

echo "✅ HTML book complete: $OUTPUT_HTML"

echo "📄 Rendering PDF..."

if ! command -v weasyprint >/dev/null 2>&1; then
  echo "❌ weasyprint not found."
  echo "Activate your venv first:"
  echo "source myvenv/bin/activate"
  exit 1
fi

weasyprint \
  --base-url "$SOURCE_DIR" \
  "$OUTPUT_HTML" \
  "$OUTPUT_PDF"

echo "✅ DONE: $OUTPUT_PDF"

if [[ -f "$WORK_DIR/contributors.txt" ]]; then
  echo "✅ Contributors listed in:"
  echo "   $WORK_DIR/contributors.txt"
fi

if [[ -f "$WORK_DIR/authors.txt" ]]; then
  echo "✅ AUTHORS.txt names listed in:"
  echo "   $WORK_DIR/authors.txt"
fi

if [[ -f "$WORK_DIR/technical-index-terms.txt" ]]; then
  echo "✅ Technical index source listed in:"
  echo "   $WORK_DIR/technical-index-terms.txt"
fi

if [[ -f "$WORK_DIR/suppressed-main-pages.txt" ]]; then
  echo "✅ Suppressed Main Page variants listed in:"
  echo "   $WORK_DIR/suppressed-main-pages.txt"
fi

if [[ -f "$WORK_DIR/suppressed-redirect-pages.txt" ]]; then
  echo "✅ Suppressed redirect pages listed in:"
  echo "   $WORK_DIR/suppressed-redirect-pages.txt"
fi

if [[ -f "$WORK_DIR/missing-images.txt" ]]; then
  echo "⚠️ Some images were still missing."
  echo "   See: $WORK_DIR/missing-images.txt"
fi
