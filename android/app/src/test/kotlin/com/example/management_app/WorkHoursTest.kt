package com.example.management_app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDateTime

/** Orele pe zile: fiecare zi cu check-in are ora ei de check-in și de check-out. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WorkHoursTest {

    private lateinit var context: Context

    private fun prefs() = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    @Test
    fun `orele pe zile se citesc din formatul scris de aplicatie`() {
        prefs().edit().putString("flutter.work_hours_b1", "1:840-660,5:960-720").commit()
        assertEquals(
            mapOf(1 to DayHours(840, 660), 5 to DayHours(960, 720)),
            BookingSettings.loadSettings(context, "b1").workHours,
        )
    }

    @Test
    fun `intrarile invalide sunt sarite`() {
        assertEquals(
            mapOf(2 to DayHours(840, 660)),
            BookingSettings.parseWorkHours("0:840-660,8:840-660,x,2:840-660,3:1440-660,4:840-1440"),
        )
    }

    @Test
    fun `nicio zi bifata inseamna nicio zi cu check-in`() {
        prefs().edit()
            .putString("flutter.work_hours_b1", "")
            .putLong("flutter.work_start_b1", 14L * 60)
            .putLong("flutter.work_end_b1", 11L * 60)
            .commit()
        assertEquals(emptyMap<Int, DayHours>(), BookingSettings.loadSettings(context, "b1").workHours)
    }

    @Test
    fun `setarile vechi devin aceleasi ore in zilele cu check-in`() {
        prefs().edit()
            .putLong("flutter.work_start_b1", 15L * 60)
            .putLong("flutter.work_end_b1", 10L * 60)
            .putString("flutter.closed_days_b1", "6,7")
            .commit()
        assertEquals(
            (1..5).associateWith { DayHours(15 * 60, 10 * 60) },
            BookingSettings.loadSettings(context, "b1").workHours,
        )
    }

    @Test
    fun `perioadele libere folosesc orele zilei de sosire`() {
        // 2030-01-14 = luni; marți fără check-in; miercuri cu alte ore.
        val settings = BoardBookingSettings(
            enabled = true,
            workHours = mapOf(1 to DayHours(14 * 60, 11 * 60), 3 to DayHours(16 * 60, 12 * 60)),
            iban = "",
        )
        val slots = DayRangeCalculator.compute(
            emptyList(), settings, LocalDateTime.of(2030, 1, 14, 8, 0),
            horizonDays = 2, nights = 2, maxResults = 10,
        )
        assertEquals(
            listOf(
                LocalDateTime.of(2030, 1, 14, 14, 0) to LocalDateTime.of(2030, 1, 16, 11, 0),
                LocalDateTime.of(2030, 1, 16, 16, 0) to LocalDateTime.of(2030, 1, 18, 12, 0),
            ),
            slots.map { it.start to it.end },
        )
    }
}
