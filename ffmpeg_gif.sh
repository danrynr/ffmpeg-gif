#!/bin/bash

# Extensions picked up by --all (case-insensitive). Add more here if needed.
video_exts="mp4|mov|mkv|avi|webm|m4v|flv|wmv|mpg|mpeg|3gp|ts|mts|m2ts|ogv"

default_width=640
max_attempts=8

# Quality ladder: "fps colors dither". Quality presets pick the starting step.
# With --keep-dimensions + --max-size, the script walks down this ladder.
levels=(
    "24 256 sierra2_4a"
    "20 192 bayer:bayer_scale=2"
    "15 128 bayer:bayer_scale=3"
    "12 96 bayer:bayer_scale=4"
    "10 64 bayer:bayer_scale=5"
    "8 48 none"
    "6 32 none"
)

usage() {
    cat <<EOF
Usage: ./ffmpeg_gif.sh [options] <input_file> <output_file>
       ./ffmpeg_gif.sh [options] --all <input_directory> [-d <output_directory>]

Options:
  -q, --quality <low|medium|high>   Output quality (default: high)
                                      high:   24 fps, 256 colors
                                      medium: 15 fps, 128 colors
                                      low:    10 fps, 64 colors
  -s, --max-size <size>             Max file size, e.g. 500K, 2M, 1.5M
  -W, --width <px>                  Max width
  -H, --height <px>                 Max height
                                    Set one or both. Aspect ratio is kept,
                                    never upscales. Default: max width $default_width
  -k, --keep-dimensions             Never shrink dimensions. Uses original size
                                    (or -W/-H if given). With -s, lowers fps and
                                    colors instead, then gifsicle --lossy if installed
  -d <dir>                          Output directory (with --all)
      --help                        Show this help
EOF
}

die() {
    echo "Error: $1" >&2
    echo "Run ./ffmpeg_gif.sh --help for more information" >&2
    exit 1
}

is_video() {
    local ext
    ext="$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')"
    [[ "$ext" =~ ^($video_exts)$ ]]
}

file_size() {
    wc -c < "$1" | tr -d ' '
}

parse_size() {
    echo "$1" | grep -Eiq '^[0-9]+(\.[0-9]+)?[KMG]?B?$' || return 1
    awk -v s="$1" 'BEGIN {
        u = toupper(s); n = u + 0
        if (u ~ /G/) n *= 1073741824
        else if (u ~ /M/) n *= 1048576
        else if (u ~ /K/) n *= 1024
        printf "%d", n
    }'
}

build_filters() {
    local fps="$1"
    local factor="$2"
    local scale=""

    if [ -n "$max_w" ] && [ -n "$max_h" ]; then
        scale="scale='min($max_w,iw)':'min($max_h,ih)':force_original_aspect_ratio=decrease:flags=lanczos"
    elif [ -n "$max_w" ]; then
        scale="scale='min($max_w,iw)':-2:flags=lanczos"
    elif [ -n "$max_h" ]; then
        scale="scale=-2:'min($max_h,ih)':flags=lanczos"
    elif [ $keep_dims -eq 0 ]; then
        scale="scale='min($default_width,iw)':-2:flags=lanczos"
    fi

    # Extra shrink step used when retrying to hit --max-size
    if [ "$factor" != "1" ]; then
        scale="$scale,scale=trunc(iw*$factor/2)*2:-2:flags=lanczos"
    fi

    if [ -n "$scale" ]; then
        echo "fps=$fps,$scale"
    else
        echo "fps=$fps"
    fi
}

# Last resort for --keep-dimensions: lossy GIF compression via gifsicle
try_gifsicle() {
    local output_file="$1"
    local tmp_gif="$2"
    local lossy size

    command -v gifsicle >/dev/null 2>&1 || {
        echo "  Tip: install gifsicle for extra lossy compression" >&2
        return 1
    }

    for lossy in 30 60 100 150 200; do
        gifsicle -O3 --lossy=$lossy "$output_file" -o "$tmp_gif" 2>/dev/null || return 1
        size=$(file_size "$tmp_gif")
        echo "  gifsicle --lossy=$lossy: $size bytes"
        if [ "$size" -le "$max_bytes" ]; then
            mv "$tmp_gif" "$output_file"
            return 0
        fi
    done

    mv "$tmp_gif" "$output_file"   # keep the smallest attempt
    return 1
}

convert_to_gif() {
    local input_file="$1"
    local output_file="$2"
    local tmp_dir palette filters size status fps colors dither
    local level=$start_level
    local factor=1
    local attempt=1

    tmp_dir="$(mktemp -d)"
    palette="$tmp_dir/palette.png"

    echo "Converting: $input_file -> $output_file"

    while true; do
        read -r fps colors dither <<< "${levels[$level]}"
        filters="$(build_filters "$fps" "$factor")"

        ffmpeg -v warning -i "$input_file" -vf "$filters,palettegen=max_colors=$colors" -y "$palette" &&
        ffmpeg -v warning -i "$input_file" -i "$palette" \
            -lavfi "$filters [x]; [x][1:v] paletteuse=dither=$dither:diff_mode=rectangle" -y "$output_file"
        status=$?

        [ $status -ne 0 ] && break
        [ -z "$max_bytes" ] && break

        size=$(file_size "$output_file")
        [ "$size" -le "$max_bytes" ] && break

        if [ $keep_dims -eq 1 ]; then
            # Same dimensions: step down fps/colors
            if [ $level -lt $((${#levels[@]} - 1)) ]; then
                level=$((level + 1))
                read -r fps colors dither <<< "${levels[$level]}"
                echo "  $size bytes > $max_size, retrying at ${fps} fps, ${colors} colors"
                continue
            fi
            try_gifsicle "$output_file" "$tmp_dir/lossy.gif" ||
                echo "Warning: could not get $output_file under $max_size at these dimensions ($(file_size "$output_file") bytes)" >&2
            break
        fi

        if [ $attempt -ge $max_attempts ]; then
            echo "Warning: could not get $output_file under $max_size after $max_attempts tries ($size bytes)" >&2
            break
        fi

        # GIF size scales roughly with pixel count, so shrink by sqrt of the overshoot
        factor=$(awk -v f="$factor" -v m="$max_bytes" -v s="$size" 'BEGIN {
            r = sqrt(m / s) * 0.95; if (r > 0.9) r = 0.9; printf "%.4f", f * r
        }')
        attempt=$((attempt + 1))
        echo "  $size bytes > $max_size, retrying smaller (attempt $attempt)"
    done

    rm -rf "$tmp_dir"
    [ $status -ne 0 ] && echo "Failed: $input_file" >&2
    return $status
}

# ---- Parse arguments ----
all=0
keep_dims=0
output_dir=""
quality="high"
max_size=""
max_bytes=""
max_w=""
max_h=""
positional=()

need_val() { [ -n "$2" ] || die "$1 requires a value"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --help)                 usage; exit 0 ;;
        --all)                  all=1; shift ;;
        -k|--keep-dimensions)   keep_dims=1; shift ;;
        -d)                     need_val "$1" "$2"; output_dir="$2"; shift 2 ;;
        -q|--quality)           need_val "$1" "$2"; quality="$2"; shift 2 ;;
        -s|--max-size)          need_val "$1" "$2"; max_size="$2"; shift 2 ;;
        -W|--width)             need_val "$1" "$2"; max_w="$2"; shift 2 ;;
        -H|--height)            need_val "$1" "$2"; max_h="$2"; shift 2 ;;
        -*)                     die "unknown option $1" ;;
        *)                      positional+=("$1"); shift ;;
    esac
done

case "$quality" in
    high)   start_level=0 ;;
    medium) start_level=2 ;;
    low)    start_level=4 ;;
    *)      die "quality must be low, medium or high" ;;
esac

if [ -n "$max_size" ]; then
    max_bytes="$(parse_size "$max_size")" || die "invalid size '$max_size' (use e.g. 500K, 2M)"
fi

for v in "$max_w" "$max_h"; do
    [ -z "$v" ] || [[ "$v" =~ ^[1-9][0-9]*$ ]] || die "width/height must be a positive integer"
done

# ---- Run ----
if [ $all -eq 1 ]; then
    input_dir="${positional[0]}"
    [ -n "$input_dir" ] && [ -d "$input_dir" ] || die "input directory not found"
    [ -z "$output_dir" ] && output_dir="$input_dir"
    mkdir -p "$output_dir"

    found=0
    for file in "$input_dir"/*; do
        [ -f "$file" ] || continue
        is_video "$file" || continue
        found=1

        name="$(basename "${file%.*}")"
        convert_to_gif "$file" "$output_dir/$name.gif"
    done

    [ $found -eq 0 ] && echo "No video files found in $input_dir"
    exit 0
fi

[ ${#positional[@]} -eq 2 ] || die "need <input_file> <output_file>"
convert_to_gif "${positional[0]}" "${positional[1]}"
exit $?
