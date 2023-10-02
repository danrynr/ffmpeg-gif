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
        echo "Usage: ./ffmpeg_gif.sh --all <input_directory> [-d <output_directory>]"
        exit 1
    fi

    if [ "$3" = "-d" ]; then
        if [ -z "$4" ]; then
            echo "Usage: ./ffmpeg_gif.sh --all <input_directory> [-d <output_directory>]"
            exit 1
        fi
        output_dir="$4"
    else
        output_dir="$2"
    fi

    if [ ! -d "$output_dir" ]; then
        mkdir "$output_dir"
    fi

    input_dir="$2"
    for file in "$input_dir"/*.mp4; do
        if [ -e "$file" ]; then
            filename="${file%.*}"
            
            if [ -z "$output_dir" ]; then
                output_file="$filename.gif"
            else
                output_file="$output_dir/$(basename "$filename").gif"
            fi
            
            convert_to_gif "$file" "$output_file"
        fi
    done
    exit 0
elif [ "$1" = "--help" ]; then
    echo "Usage: ./ffmpeg_gif.sh <input_file> <output_file>"
    echo "       ./ffmpeg_gif.sh --all <input_directory> [-d <output_directory>]"
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
