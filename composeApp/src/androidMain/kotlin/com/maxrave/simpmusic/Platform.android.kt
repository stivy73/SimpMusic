package com.maxrave.simpmusic

import android.os.Build

actual fun getPlatform(): Platform = Platform.Android

/**
 * Android 16's HWUI can recurse indefinitely while preparing the RenderNode tree created by the
 * Kyant backdrop effect. The failure is a native SIGSEGV, so Kotlin cannot catch it. Keep the
 * existing flat surfaces on API 36+ until that renderer combination is safe again.
 */
actual fun supportsLiquidGlassRendering(): Boolean = supportsLiquidGlassRenderingOnAndroid(Build.VERSION.SDK_INT)
