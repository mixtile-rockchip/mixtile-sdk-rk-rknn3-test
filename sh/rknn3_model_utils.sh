#!/usr/bin/env bash

# ===========================================
# RKNN3 Model File Utilities
# Common functions for finding model files flexibly
# ===========================================

# Auto-detect model files using flexible pattern matching
# This function searches for files matching: *{keyword}*{model_name}*{extension} OR *{model_name}*{keyword}*{extension}
# Args:
#   $1 = model_dir: Base model directory or path
#   $2 = keyword: Search keyword (e.g., "vision", "llm"), optional - leave empty for no keyword
#   $3 = extension: File extension (e.g., ".rknn", ".weight", ".tokenizer.gguf")
# Returns: Found file path (or empty if not found)
find_model_file() {
    local model_dir="$1"
    local keyword="$2"
    local extension="$3"

    local model_name=$(basename "$model_dir")
    local dir=$(dirname "$model_dir")

    # If model_dir is a directory, search in it; otherwise search in parent dir
    local search_dir="$dir"
    if [ -d "$model_dir" ]; then
        search_dir="$model_dir"
    fi

    local found
    if [ -n "$keyword" ]; then
        # With keyword: match files containing both model_name and keyword in any order
        # Pattern: *keyword*model_name*extension OR *model_name*keyword*extension
        found=$(find "$search_dir" -maxdepth 1 -type f -iname "*${extension}" 2>/dev/null | \
            grep -iE "(${keyword}.*${model_name}|${model_name}.*${keyword})" | \
            head -n 1)
    else
        # Without keyword: just match files containing model_name with extension
        # Pattern: *model_name*extension
        found=$(find "$search_dir" -maxdepth 1 -type f -iname "*${model_name}*${extension}" 2>/dev/null | \
            head -n 1)
    fi

    echo "$found"
}

# Wrapper function for common files (tokenizer, embedding, etc.) without keyword
# This is just a convenience wrapper that calls find_model_file with empty keyword
# Args:
#   $1 = model_dir: Base model directory or path
#   $2 = extension: File extension (e.g., ".tokenizer.gguf", ".embed.bin", ".ini")
# Returns: Found file path (or empty if not found)
find_common_file() {
    find_model_file "$1" "" "$2"
}
