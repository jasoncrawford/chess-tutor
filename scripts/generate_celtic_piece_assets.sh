#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PIECES_DIR="$ROOT_DIR/ChessTutor/Resources/Assets.xcassets/Pieces"
BASE_URL="https://raw.githubusercontent.com/lichess-org/lila/master/public/piece/celtic"

mkdir -p "$PIECES_DIR"

write_contents_json() {
  local asset_dir="$1"
  local filename="$2"

  cat > "$asset_dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$filename",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
JSON
}

recolor_svg() {
  local color="$1"
  local source_svg="$2"
  local destination_svg="$3"

  python3 - "$color" "$source_svg" "$destination_svg" <<'PY'
import sys
from pathlib import Path

color, source_path, destination_path = sys.argv[1:4]
svg = Path(source_path).read_text()

if color == "white":
    replacements = {
        "#fff": "#fff7e4",
        "#bfd3d7": "#d9bd83",
        "stroke:#000": "stroke:#5f4428",
    }
elif color == "black":
    replacements = {
        "#7f899b": "#6d5637",
        "#1c1c2f": "#201911",
        "stroke:#000": "stroke:#120d08",
    }
else:
    raise ValueError(f"Unknown piece color: {color}")

for original, replacement in replacements.items():
    svg = svg.replace(original, replacement)

Path(destination_path).write_text(svg)
PY
}

fetch_piece() {
  local source_name="$1"
  local asset_name="$2"
  local color="$3"
  local asset_dir="$PIECES_DIR/$asset_name.imageset"
  local output_svg="$asset_dir/$asset_name.svg"
  local source_svg

  mkdir -p "$asset_dir"
  source_svg="$(mktemp)"
  curl -fsSL "$BASE_URL/$source_name.svg" -o "$source_svg"
  recolor_svg "$color" "$source_svg" "$output_svg"
  rm -f "$source_svg"
  write_contents_json "$asset_dir" "$asset_name.svg"
}

fetch_piece wK PieceWhiteKing white
fetch_piece wQ PieceWhiteQueen white
fetch_piece wR PieceWhiteRook white
fetch_piece wB PieceWhiteBishop white
fetch_piece wN PieceWhiteKnight white
fetch_piece wP PieceWhitePawn white
fetch_piece bK PieceBlackKing black
fetch_piece bQ PieceBlackQueen black
fetch_piece bR PieceBlackRook black
fetch_piece bB PieceBlackBishop black
fetch_piece bN PieceBlackKnight black
fetch_piece bP PieceBlackPawn black

echo "Generated Celtic piece assets in $PIECES_DIR"
