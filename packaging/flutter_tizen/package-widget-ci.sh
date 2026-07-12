#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: package-widget-ci.sh <staged-widget> [...]" >&2
  exit 2
fi

for widget_dir in "$@"; do
  if [ ! -f "$widget_dir/config.xml" ]; then
    echo "staged widget is missing config.xml: $widget_dir" >&2
    exit 1
  fi

  WIDGET_DIR="$widget_dir" expect -c '
    set timeout -1
    set widget_dir $env(WIDGET_DIR)
    spawn tizen package -t wgt -- $widget_dir
    expect "Author password:"
    send -- "123456\r"
    expect {
      "Yes: (Y), No: (N) ?" {
        send -- "N\r"
        exp_continue
      }
      eof
    }
  '

  generated_wgt="$widget_dir/Moonlight Flutter.wgt"
  artifact_wgt="$widget_dir/MoonlightFlutter.wgt"
  if [ -f "$generated_wgt" ]; then
    mv -- "$generated_wgt" "$artifact_wgt"
  elif [ ! -f "$artifact_wgt" ]; then
    echo "Tizen packaging did not create the expected widget in $widget_dir" >&2
    exit 1
  fi
done
