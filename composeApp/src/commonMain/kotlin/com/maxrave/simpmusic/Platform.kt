package com.maxrave.simpmusic

sealed class Platform {
    object Android : Platform()
    object iOS : Platform()
    object Desktop : Platform()

    fun osName(): String = when (this) {
        Android -> "android"
        iOS -> "iOS"
        Desktop -> System.getProperty("os.name") ?: "jvm"
    }
}

expect fun getPlatform(): Platform

/** Whether the current graphics stack can safely render the Kyant backdrop effect. */
expect fun supportsLiquidGlassRendering(): Boolean

internal fun supportsLiquidGlassRenderingOnAndroid(apiLevel: Int): Boolean = apiLevel < 36
