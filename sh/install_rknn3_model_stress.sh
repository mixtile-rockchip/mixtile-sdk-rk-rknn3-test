#!/usr/bin/env bash
# file: install_rknn_demos.sh

set -e

BIN_LIST=(
    rknn3_cnn_demo
    rknn3_llm_demo
    rknn3_vlm_demo
)

for bin in "${BIN_LIST[@]}"; do
    if [[ ! -f "$bin" ]]; then
        echo "ERROR: $bin no exist，please check" >&2
        exit 1
    fi
    echo "Installing $bin -> /usr/bin/$bin"
    cp -f "$bin" /usr/bin/
    chmod 777 /usr/bin/"$bin"
done

chmod 777 *.sh
echo "Done. all demo install and chmod 777."
