package com.example.strumcoach

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** 承诺“不联网、不收集数据、没有账号和内购”：清单里不能出现联网权限，依赖里不能出现统计、广告、支付 SDK。 */
class PrivacyTest {
    private val root = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "settings.gradle.kts").exists() }

    @Test fun manifestHasNoNetworkPermission() {
        val manifest = File(root, "app/src/main/AndroidManifest.xml").readText()
        assertFalse(manifest.contains("android.permission.INTERNET"))
        assertFalse(manifest.contains("ACCESS_NETWORK_STATE"))
        assertTrue(manifest.contains("android.permission.RECORD_AUDIO"))
        assertTrue(manifest.contains("allowBackup=\"false\""))
    }

    @Test fun noTrackingAdsOrBillingDependencies() {
        val text = File(root, "gradle/libs.versions.toml").readText() + File(root, "app/build.gradle.kts").readText()
        for (word in listOf("firebase", "crashlytics", "admob", "play-services", "billing", "analytics", "sentry", "facebook", "appsflyer", "adjust")) {
            assertFalse("依赖里不该有 $word", text.lowercase().contains(word))
        }
    }

    @Test fun noKeysOrKeystoresInTheTree() {
        val bad = root.walkTopDown().onEnter { it.name != "build" && it.name != ".gradle" && it.name != ".kotlin" }
            .filter { it.isFile && (it.extension in setOf("jks", "keystore", "p12", "pem")) }.toList()
        assertTrue("不该有密钥文件：$bad", bad.isEmpty())
        assertFalse(File(root, "app/build.gradle.kts").readText().contains("signingConfigs"))
    }
}
