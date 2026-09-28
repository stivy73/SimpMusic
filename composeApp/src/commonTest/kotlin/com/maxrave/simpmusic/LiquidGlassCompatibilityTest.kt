package com.maxrave.simpmusic

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiquidGlassCompatibilityTest {
    @Test
    fun android15KeepsLiquidGlassAvailable() {
        assertTrue(supportsLiquidGlassRenderingOnAndroid(apiLevel = 35))
    }

    @Test
    fun android16DisablesUnsafeBackdropRenderer() {
        assertFalse(supportsLiquidGlassRenderingOnAndroid(apiLevel = 36))
    }

    @Test
    fun newerAndroidVersionsRemainOnSafeFallback() {
        assertFalse(supportsLiquidGlassRenderingOnAndroid(apiLevel = 37))
    }
}
