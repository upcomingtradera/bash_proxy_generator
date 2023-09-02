#!/bin/bash

# Usage function to display script usage
function usage() {
    echo "Usage: $0 [input directory] [output directory] [bitrate] [bufsize] [--cuda]"
    echo "  input directory: directory containing video files to process"
    echo "  output directory: directory to save processed video files"
    echo "  bitrate: (optional) target bitrate for output files, default is 8M"
    echo "  bufsize: (optional) buffer size for output files, default is 2x bitrate"
    echo "  --cuda: (optional) use CUDA for GPU-based encoding"
    exit 1
}

# Check command line arguments
if [ "$#" -lt 2 ]; then
    usage
fi

# Initialize CUDA flag to 0
use_cuda=0

# Get command line arguments and set CUDA flag
for arg in "$@"; do
  case $arg in
    --cuda)
      use_cuda=1
      shift
      ;;
  esac
done

input_dir=$1
output_dir=$2
bitrate=${3:-8M}
bufsize=${4:-$(echo $bitrate | sed 's/M//' | awk '{print $1 * 2}')M}


# Check if input directory exists
if [ ! -d "$input_dir" ]; then
    echo "Input directory does not exist: $input_dir"
    exit 1
fi

# Check if output directory exists
if [ ! -d "$output_dir" ]; then
    echo "Output directory does not exist: $output_dir"
    exit 1
fi

# Create error directory if it doesn't exist
error_dir="$output_dir/_error"
mkdir -p "$error_dir"

# Loop through all video files in the input directory
for input_file in "$input_dir"/*.{mov,mp4,avi,mkv}; do
    # Check if file exists
    if [ ! -f "$input_file" ]; then
        continue
    fi

    # Prepare output file path
    filename=$(basename "$input_file")
    filename_no_ext="${filename%.*}"
    output_file="$output_dir/${filename_no_ext}_proxy.mov"

    # If output file already exists, remove input file from list
    if [ -f "$output_file" ]; then
        continue
    fi

    # Estimate output file size (in kilobytes) and available disk space (in kilobytes)
    estimated_size=$(echo $bitrate | sed 's/M//' | awk -v duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file") '{print duration * $1 * 125}') # Estimated size in KB
    available_space=$(df "$output_dir" | tail -1 | awk '{print $4}') # Available space in KB

    # Add 10% padding to the estimated size
    estimated_size=$(awk -v size=$estimated_size 'BEGIN {print int(size * 1.1)}')

    # Check if there is enough free space
    if (( estimated_size > available_space )); then
        echo "Not enough free space in output directory for: $input_file"
        continue
    else
        echo "Enough free space available for: $input_file"
    fi


    if [ "$use_cuda" -eq 1 ]; then
        ffmpeg_command="ffmpeg -hwaccel cuda -i \"$input_file\" -c:v h264_nvenc -pix_fmt yuv420p -preset slow -maxrate $bitrate -bufsize $bufsize -c:a pcm_s16le -ar 48000 \"$output_file\" -loglevel quiet -stats"
    else
        ffmpeg_command="ffmpeg -i \"$input_file\" -c:v libx264 -pix_fmt yuv420p -preset ultrafast -maxrate $bitrate -bufsize $bufsize -c:a pcm_s16le -ar 48000 \"$output_file\" -loglevel quiet -stats"
    fi

    if ! eval $ffmpeg_command; then
        echo "Error encoding file: $input_file"
        mv "$input_file" "$error_dir"
    fi

done

