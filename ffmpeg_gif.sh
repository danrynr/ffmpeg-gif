#!/bin/bash

palette="/tmp/palette.png"
filters="fps=24,scale=640:-1:flags=lanczos"

convert_to_gif() {
    input_file="$1"
    output_file="$2"

    ffmpeg -v warning -i "$input_file" -vf "$filters,palettegen" -y "$palette"
    ffmpeg -v warning -i "$input_file" -i "$palette" -lavfi "$filters [x]; [x][1:v] paletteuse" -y "$output_file"
}

if [ "$1" = "--all" ]; then
    if [ -z "$2" ]; then
        echo "Usage: ./ffmpeg_gif.sh --all <input_folder>"
        exit 1
    fi

    input_folder="$2"
    for file in "$input_folder"/*.mp4; do
        if [ -e "$file" ]; then
            filename="${file%.*}"
            convert_to_gif "$file" "$filename.gif"
        fi
    done
    exit 0
elif [ "$1" = "--help" ]; then
    echo "Usage: ./ffmpeg_gif.sh [--single] <input_file> <output_file>"
    echo "       ./ffmpeg_gif.sh --all <input_folder>"
    echo "If --single is not specified, then all mp4 files in the current directory will be converted to gif. All output files will be named <input_file>.gif"
    exit 0
fi

if [ -n "$1" ]; then
    if [ -n "$2" ]; then
        convert_to_gif "$1" "$2"
        exit 0
    else
        echo "Invalid argument. Run ./ffmpeg_gif.sh --help for more information"
        exit 1
    fi
fi

for file in *.mp4; do
    if [ -e "$file" ]; then
        filename="${file%.*}"
        convert_to_gif "$file" "$filename.gif"
    fi
done
