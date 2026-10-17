#!/bin/bash
# sweep.sh BLOB PARAM_INDEX(1..7) "values" "base params" [BLOCKS] [anal.py|anal2.py]
# Renders one note per value with that knob changed; prints the analysis line.
# TXRUN defaults to ~/dsp/dsp56300/txrun.
HERE=$(cd "$(dirname "$0")" && pwd)
TXRUN=${TXRUN:-~/dsp/dsp56300/txrun}
BLOB=$1; K=$2; VALS=$3; BASE=($4); BL=${5:-500}; AN=${6:-anal.py}
for v in $VALS; do
  P=("${BASE[@]}"); P[$((K-1))]=$v
  TXOUT=/tmp/sw.f32 $TXRUN "$BLOB" $BL "${P[@]}" > /dev/null
  printf '%s=%3d  ' "$K" "$v"
  python3 -I "$HERE/$AN" /tmp/sw.f32 quiet
done
