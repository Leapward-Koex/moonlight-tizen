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

  expect -c '
    set timeout -1
    set widget_dir [lindex $argv 0]
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
  ' "$widget_dir"

  if [ ! -f "$widget_dir/MoonlightFlutter.wgt" ]; then
    echo "Tizen packaging did not create MoonlightFlutter.wgt in $widget_dir" >&2
    exit 1
  fi
done
