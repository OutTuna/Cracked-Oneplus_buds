#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
swift build -c release --product enco
swift build -c release --product EncoChecks
bin_path=$(swift build -c release --show-bin-path)
"$bin_path/EncoChecks"
mkdir -p bin
cp "$bin_path/enco" bin/enco
echo "Built bin/enco"
