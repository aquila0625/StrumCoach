package com.example.tunebeatchord.chord

import com.example.tunebeatchord.tuner.NoteNaming

/** 根音名，用惯用拼法（C♯ E♭ F♯ A♭ B♭），随唱名、德语写法变化，例如 "C♯"、"Do♯"、"B"（德语的 B♭）。 */
fun NoteNaming.rootName(chord: Chord) = rootName(chord.root)

fun NoteNaming.rootName(pitchClass: Int) = name(pitchClass, useFlats = ChordSpelling.rootUsesFlats(pitchClass))

/** 完整和弦名，例如 "Cmaj7"、"E♭m"、"Rem"、"Sol7"。大三没有后缀，小三是 m。 */
fun NoteNaming.chordName(chord: Chord) = rootName(chord) + chord.type.symbol

/** 和弦名：指定根音音级和类型（类型按钮用）。 */
fun NoteNaming.chordName(pitchClass: Int, type: ChordType) = rootName(pitchClass) + type.symbol

/** 组成音，拼法和根音一致，例如 E♭ 大三为 ["E♭", "G", "B♭"]。 */
fun NoteNaming.toneNames(chord: Chord): List<String> =
    chord.pitchClasses.zip(ChordSpelling.flats(chord)).map { (pc, flat) -> name(pc, useFlats = flat) }

/** 和弦里某个音级的音名（指法图弦下面的字母用）。 */
fun NoteNaming.toneName(pitchClass: Int, chord: Chord) =
    name(pitchClass, useFlats = ChordSpelling.usesFlat(pitchClass, chord))

/** 根音按钮上的写法：只用常用的一种（C♯ E♭ F♯ A♭ B♭），唱名模式是 Do♯ Mi♭ Fa♯ La♭ Si♭，德语的 B♭ 写作 B。 */
fun NoteNaming.rootButtonName(pitchClass: Int) = rootName(pitchClass)
