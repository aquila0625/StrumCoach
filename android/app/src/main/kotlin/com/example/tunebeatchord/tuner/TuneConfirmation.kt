package com.example.tunebeatchord.tuner

import kotlin.math.abs

/**
 * 判定“某个音调准了”：偏差持续在准音区内一段时间才算，且同一个音只提示一次。
 *
 * - 目标音（弦、或半音阶模式下的音名）的偏差**连续** `holdSeconds`（默认 0.5 秒）都在 ±`tuneCents`（默认 ±5 音分）以内，才触发一次 [Event.Tuned]；
 * - 触发后这个音被“锁住”，不会再提示；偏出 ±`rearmCents`（默认 ±10 音分）时解锁（给 [Event.Drifted]），再回到准音区才会再次提示；
 * - 目标换了、信号丢了、偏差超出准音区，持续时间都从头算。
 *
 * 纯逻辑、不碰音频，时间由调用方传入，所以可以在测试里精确地推进。
 */
class TuneConfirmation(
    var holdSeconds: Double = 0.5,
    var tuneCents: Double = TunerDefaults.IN_TUNE_CENTS,
    var rearmCents: Double = 10.0,
) {
    sealed interface Event {
        /** 这个音刚刚调准。 */
        data class Tuned(val key: Int) : Event

        /** 这个音（已调准过）偏出了解锁范围，可以再次提示。 */
        data class Drifted(val key: Int) : Event
    }

    private var holdKey: Int? = null
    private var holdStart = 0.0
    private val latched = mutableSetOf<Int>()

    fun isLatched(key: Int) = key in latched

    fun reset() {
        holdKey = null
        latched.clear()
    }

    /** 只清掉“正在计时”的状态，保留已提示过的音（例如暂停检测之后继续）。 */
    fun restartHold() {
        holdKey = null
    }

    /** 喂入一次结果。没有信号时 key 和 cents 都传 null。 */
    fun update(key: Int?, cents: Double?, now: Double): Event? {
        if (key == null || cents == null) {
            holdKey = null
            return null
        }
        val deviation = abs(cents)
        var event: Event? = null
        if (deviation > rearmCents && latched.remove(key)) event = Event.Drifted(key)

        if (deviation > tuneCents) {
            holdKey = null
            return event
        }
        if (holdKey != key) {
            holdKey = key
            holdStart = now
        }
        if (key !in latched && now - holdStart >= holdSeconds) {
            latched.add(key)
            return Event.Tuned(key)
        }
        return event
    }
}
