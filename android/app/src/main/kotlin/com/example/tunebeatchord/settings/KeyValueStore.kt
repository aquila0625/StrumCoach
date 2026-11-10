package com.example.tunebeatchord.settings

import android.content.Context
import android.content.SharedPreferences

/** 本机的小型键值存储：App 里用 SharedPreferences，测试里用内存。全部只存在设备上。 */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
}

class MemoryStore : KeyValueStore {
    private val map = HashMap<String, String>()
    override fun getString(key: String) = map[key]
    override fun putString(key: String, value: String?) {
        if (value == null) map.remove(key) else map[key] = value
    }
}

class PrefsStore(private val prefs: SharedPreferences) : KeyValueStore {
    constructor(context: Context, name: String) : this(context.getSharedPreferences(name, Context.MODE_PRIVATE))

    override fun getString(key: String) = prefs.getString(key, null)
    override fun putString(key: String, value: String?) {
        prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }
}

/** 每个键存成目录里的一个文件：数据多一些的东西（练习记录）用它，不用把整份 SharedPreferences 都读进内存。 */
class FileStore(private val dir: java.io.File) : KeyValueStore {
    init {
        dir.mkdirs()
    }

    private fun file(key: String) = java.io.File(dir, key.replace(Regex("[^A-Za-z0-9._-]"), "_") + ".json")

    override fun getString(key: String): String? = file(key).takeIf { it.exists() }?.let { runCatching { it.readText() }.getOrNull() }

    override fun putString(key: String, value: String?) {
        val f = file(key)
        if (value == null) {
            f.delete(); return
        }
        // 先写临时文件再改名，写到一半断电也不会留下半份数据
        val tmp = java.io.File(dir, f.name + ".tmp")
        tmp.writeText(value)
        if (!tmp.renameTo(f)) {
            f.writeText(value); tmp.delete()
        }
    }
}
