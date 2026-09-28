package com.maxrave.simpmusic.utils

object DisplayMode {
    const val PREFERENCE_KEY = "display_mode"
    const val AUTOMATIC = "automatic"
    const val STANDARD = "standard"
    const val CAR = "car"

    fun usesCarLayout(
        mode: String,
        isAndroid: Boolean,
        widthDp: Int,
        heightDp: Int,
    ): Boolean {
        if (!isAndroid) return false
        return when (mode) {
            CAR -> true
            STANDARD -> false
            else -> {
                val aspectRatio = if (heightDp > 0) widthDp.toFloat() / heightDp else 0f
                aspectRatio >= 1.55f &&
                    ((widthDp >= 900 && heightDp in 320..600) ||
                        (widthDp >= 1100 && heightDp in 320..720))
            }
        }
    }
}
