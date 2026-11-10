#!/bin/zsh
# 多语言截图：英文、日文、德文、西班牙文的主界面和和弦库（深色），存到 screenshots/i18n/。
# 用法：zsh tools/l10n/shots_i18n.sh <模拟器 UDID>
set -e
D=${1:?simulator udid}
APP=${0:a:h:h:h}
OUT=$APP/screenshots/i18n
mkdir -p $OUT
typeset -A LOCALE=(en en_US ja ja_JP de de_DE es es_ES ru ru_RU fr fr_FR)
shoot() { # name lang args...
  local name=$1 lang=$2; shift 2
  xcrun simctl terminate $D com.example.strumcoach >/dev/null 2>&1 || true
  xcrun simctl launch $D com.example.strumcoach -demo YES -appearance dark \
    -AppleLanguages "($lang)" -AppleLocale "${LOCALE[$lang]}" "$@" >/dev/null
  sleep 7
  xcrun simctl io $D screenshot $OUT/$name-$lang.png >/dev/null 2>&1
}
for lang in en ja de es; do
  shoot metronome $lang -demoTab metronome
  shoot chords $lang -demoTab chords
done
# 额外检查长词：德语、俄语的节奏设置、训练、设置页、我的；法语的和弦库（唱名）
for lang in de ru; do
  shoot rhythm $lang -demoSheet rhythm
  shoot training $lang -demoTab training
  shoot settings $lang -demoTab profile -demoSheet settings
  shoot profile $lang -demoTab profile
  shoot tuner $lang -demoTab tuner
done
shoot chords fr -demoTab chords
echo done
