package com.maxrave.simpmusic.utils

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DisplayModeTest {
    @Test
    fun automaticRecognizesWideShortOttocastWindow() {
        assertTrue(DisplayMode.usesCarLayout(DisplayMode.AUTOMATIC, true, 1280, 600))
        assertTrue(DisplayMode.usesCarLayout(DisplayMode.AUTOMATIC, true, 1280, 720))
    }

    @Test
    fun automaticKeepsPhoneAndTabletLayoutsStandard() {
        assertFalse(DisplayMode.usesCarLayout(DisplayMode.AUTOMATIC, true, 800, 360))
        assertFalse(DisplayMode.usesCarLayout(DisplayMode.AUTOMATIC, true, 1280, 800))
        assertFalse(DisplayMode.usesCarLayout(DisplayMode.AUTOMATIC, true, 600, 1280))
    }

    @Test
    fun explicitSelectionOverridesGeometry() {
        assertTrue(DisplayMode.usesCarLayout(DisplayMode.CAR, true, 600, 1280))
        assertFalse(DisplayMode.usesCarLayout(DisplayMode.STANDARD, true, 1280, 600))
        assertFalse(DisplayMode.usesCarLayout(DisplayMode.CAR, false, 1280, 600))
    }
}
