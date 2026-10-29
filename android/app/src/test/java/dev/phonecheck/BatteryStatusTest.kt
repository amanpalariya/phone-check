package dev.phonecheck

import org.junit.Assert.*
import org.junit.Test

class BatteryStatusTest {
    @Test fun normalizesPlatformScaleAndUnknownReadings() {
        assertEquals(BatteryStatus(75, true), BatteryStatus.from(150, 200, true, true))
        assertEquals(BatteryStatus(0, false), BatteryStatus.from(0, 100, true, false))
        assertEquals(BatteryStatus(100, true), BatteryStatus.from(Int.MAX_VALUE, Int.MAX_VALUE, true, true))
        for ((level, scale) in listOf(-1 to 100, 1 to 0, 101 to 100)) {
            assertNull(BatteryStatus.from(level, scale, true, false).percentage)
        }
        assertEquals(BatteryStatus(null, false), BatteryStatus.from(50, 100, false, true))
    }
    @Test fun encodesUnknownWithoutInventingZeroPercent() {
        assertTrue(BatteryStatus(null, false).json().isNull("percentage"))
        val battery = BatteryStatus(42, true, powerSaving = true).json()
        assertEquals(42, battery.getInt("percentage"))
        assertTrue(battery.getBoolean("charging"))
        assertTrue(battery.getBoolean("powerSaving"))
    }
}
