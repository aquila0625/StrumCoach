package com.example.strumcoach.i18n

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** 译文的完整性：源码里用到的每个中文键都有译文，每种语言都有全部键，占位符一致。 */
class StringsCoverageTest {
    private val root = generateSequence(File("").absoluteFile) { it.parentFile }
        .first { File(it, "settings.gradle.kts").exists() }
    private val res = File(root, "app/src/main/res")
    private val kotlinDir = File(root, "app/src/main/kotlin")

    private val keyPattern = Regex("""\b(?:tr|trPlural|t|plural)\(\s*"((?:[^"\\]|\\.)*)"""")

    private fun unescape(s: String) = s.replace("\\\"", "\"").replace("\\\\", "\\")

    @Test fun everyKeyUsedInSourceHasATranslation() {
        val used = kotlinDir.walkTopDown().filter { it.extension == "kt" && !it.name.startsWith("StringTable") }
            .flatMap { f -> keyPattern.findAll(f.readText()).map { f.name to unescape(it.groupValues[1]) } }
            .filter { (_, key) -> key.any { it.code > 127 } || key.contains("%") }   // 只检查含中文或占位符的键
            .toList()
        val missing = used.filter { (_, k) -> k !in StringTable.strings && k !in StringTable.plurals }
        assertTrue("这些键没有译文：$missing", missing.isEmpty())
        assertTrue(used.isNotEmpty())
    }

    private fun entries(dir: String): Map<String, String> {
        val text = File(res, "$dir/strings.xml").readText()
        val out = LinkedHashMap<String, String>()
        Regex("""<string name="(\w+)">(.*?)</string>""", RegexOption.DOT_MATCHES_ALL).findAll(text).forEach { out[it.groupValues[1]] = it.groupValues[2] }
        Regex("""<plurals name="(\w+)">(.*?)</plurals>""", RegexOption.DOT_MATCHES_ALL).findAll(text).forEach { out[it.groupValues[1]] = it.groupValues[2] }
        return out
    }

    private fun placeholders(s: String) =
        Regex("""%(?:\d+\$)?[sd]""").findAll(s).map { it.value.replace(Regex("""\d+\$"""), "") }.sorted().toList()

    @Test fun everyLanguageHasEveryKeyWithMatchingPlaceholders() {
        val dirs = res.listFiles { f -> f.isDirectory && f.name.startsWith("values") && File(f, "strings.xml").exists() }!!.map { it.name }
        assertEquals("应有 12 种语言", 12, dirs.size)
        val zh = entries("values-b+zh+Hans")
        assertTrue(zh.size > 400)
        for (dir in dirs) {
            val e = entries(dir)
            assertEquals("$dir 的条目数", zh.size, e.size)
            for ((k, v) in e) {
                if (k == "app_name" || k == "mic_usage") continue
                val expected = placeholders(zh.getValue(k).split("</item>").first())
                val got = placeholders(v.split("</item>").first())
                assertEquals("$dir / $k 的占位符", expected, got)
            }
        }
    }

    @Test fun everyIdInTheTableExistsInTheResources() {
        val en = entries("values")
        val ids = Regex("""R\.(?:string|plurals)\.(\w+)""").findAll(File(kotlinDir, "com/example/strumcoach/i18n/StringTable.kt").readText())
            .map { it.groupValues[1] }.toList()
        assertEquals(419, ids.size)
        assertTrue(ids.all { it in en })
    }
}
