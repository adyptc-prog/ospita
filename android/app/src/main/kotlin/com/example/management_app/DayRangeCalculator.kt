package com.example.management_app

import java.time.LocalDateTime

/** O perioadă liberă: [start, end) — check-in → check-out. */
data class FreeSlot(val start: LocalDateTime, val end: LocalDateTime)

/**
 * Calculează perioadele libere ale unui tabel — lungimea sejurului e variabilă
 * (aleasă de client prin SMS) și un sejur trece peste granița zilei
 * calendaristice. Folosit atât de „Spatiere” din aplicație, cât și de botul
 * SMS de rezervări.
 *
 * Scanează orizontul zi cu zi și, pentru fiecare zi candidată de check-in,
 * verifică dacă intervalul [check-in, check-in + nights) se suprapune cu
 * vreun sejur deja ocupat ([BusyInterval] din [BookingSettings.loadZileBusyRanges]).
 */
object DayRangeCalculator {

    fun compute(
        busy: List<BusyInterval>,
        settings: BoardBookingSettings,
        from: LocalDateTime,
        horizonDays: Int,
        nights: Int,
        maxResults: Int,
    ): List<FreeSlot> {
        if (nights <= 0 || maxResults <= 0) return emptyList()
        val sortedBusy = busy.sortedBy { it.startMin }
        val result = mutableListOf<FreeSlot>()

        var day = from.toLocalDate()
        val lastDay = day.plusDays(horizonDays.toLong())

        while (!day.isAfter(lastDay) && result.size < maxResults) {
            // Orele țin de ziua sosirii; fără ele, în acea zi nu se face check-in.
            val hours = settings.workHours[day.dayOfWeek.value]
            if (hours != null) {
                val checkIn = day.atStartOfDay().plusMinutes(hours.checkInMin.toLong())
                val checkOut = day.plusDays(nights.toLong())
                    .atStartOfDay().plusMinutes(hours.checkOutMin.toLong())

                if (!checkIn.isBefore(from)) {
                    val overlaps = sortedBusy.any {
                        it.startMin.isBefore(checkOut) && it.endMin.isAfter(checkIn)
                    }
                    if (!overlaps) result.add(FreeSlot(checkIn, checkOut))
                }
            }
            day = day.plusDays(1)
        }

        return result
    }
}
