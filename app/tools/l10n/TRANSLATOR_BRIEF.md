# Translator brief

App: iPhone practice app for musicians: tuner, metronome, chord library and strum training. Chinese name 扫弦教练, English name **StrumCoach**. Source language: Simplified Chinese.

Input: `tools/l10n/source.json` (relative to `app/`): array of `{key, modules, where, note}`.
- `key`: Simplified Chinese source text.
- `note`: English context (may be empty).
- `where`: Swift `file:line` where it appears. You may read those files to understand context (`app/StrumCoach`, `app/MetronomeCore/Sources`, `Packages/TunerKit/Sources`, `Packages/ChordKit/Sources`). **Do not edit any source file.**

Output: for each assigned language, write `tools/l10n/translations/<lang>.json`: one JSON object mapping **every** key in source.json to its translation. UTF-8, non-ASCII kept as-is, no extra keys. Write only your assigned files.

## Rules

1. **Placeholders**: every `%@` and `%lld` in the key must appear in the translation the same number of times with the same types. If the language needs a different order, use positional forms (`%1$lld`, `%2$@`) for all placeholders in that string. Never add placeholders. Keep tokens like BPM, TAP, Hz, A4, Drop D, DADGAD and note-letter groups (EADG, GCEA, GDAE, CGDA, BEADG, E♭) unchanged.
2. **Length**: short, natural, polished iOS wording. Tab labels ≤ ~10 characters; chip captions and button labels short; avoid long compound words where a shorter common term exists (especially German and Russian). Use the platform's standard terms (Settings, Done, OK, Cancel …) as Apple uses them in that language.
3. **Musical terms**: use the term musicians actually use in that language (beat, bar/measure, time signature, subdivision, triplet, dotted, syncopation, accent, cents, open position, barre, root, third, fifth, octave, tuning, in tune / flat / sharp, woodblock, cowbell).
4. **Chord type buttons** `大三` / `小三`: very short (e.g. en "Maj"/"Min", de "Dur"/"Moll", fr "Maj"/"Min"). Full names (`大三和弦` …) are normal chord-type names.
5. **Tempo terms**: keys whose note starts with `TEMPO-LOCAL <Italian>` are the LOCAL name of an Italian tempo marking. The UI shows `<local> <Italian>` (e.g. "快板 Allegro").
   - Italian (`it`) and English (`en`): write the Italian word itself (快板 → "Allegro"), so only the Italian is shown.
   - Japanese: katakana reading of the Italian term (快板 → アレグロ, 行板 → アンダンテ).
   - Traditional Chinese: the traditional Chinese term (快板, 廣板, 柔板 …).
   - Korean: the Korean musical term (e.g. 빠르게 for Allegro, 느리게 for Adagio) — short.
   - Other languages: a short descriptive word in that language (de Allegro → "schnell", fr → "rapide", es → "rápido", pt-BR → "rápido", ru → "быстро", tr → "hızlı"). Keep it to 1–2 words.
6. **Brand**: the app name comes from InfoPlist (CFBundleDisplayName), not from these keys: 扫弦教练 in Chinese, "StrumCoach" elsewhere.
7. Key `，` is a VoiceOver list separator: use the language's normal separator (en ", ", ja "、", zh-Hant "，", de ", " …).
8. `pt-BR` is Brazilian Portuguese; `zh-Hant` is Traditional Chinese (Taiwan/Hong Kong usage: 設定, 檢視, 調音器, 節拍器, 和弦庫).

## Check before finishing

```bash
cd app
python3 -I tools/l10n/check.py <lang> [<lang> …]
```
It lists missing keys and placeholder mismatches. Fix everything it reports, then report briefly (in English) which files you wrote and any keys you were unsure about.
