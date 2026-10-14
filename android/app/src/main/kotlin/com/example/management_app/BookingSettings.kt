package com.example.management_app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

data class BoardInfo(val id: String, val name: String)

// Orele sejururilor care încep într-o anumită zi a săptămânii (minute de la
// miezul nopții): check-in în ziua sosirii, check-out în ziua plecării.
data class DayHours(val checkInMin: Int, val checkOutMin: Int)

data class BoardBookingSettings(
    val enabled: Boolean,
    // Zilele în care se acceptă check-in (1=luni .. 7=duminică, la fel ca
    // DateTime.weekday din Dart), fiecare cu orele ei; în zilele care lipsesc
    // nu se face check-in.
    val workHours: Map<Int, DayHours>,
    // Cont bancar afișat clientului în SMS-ul „așteaptă validarea plății”.
    // Gol dacă proprietarul nu l-a completat.
    val iban: String,
)

data class BusyInterval(val startMin: LocalDateTime, val endMin: LocalDateTime)

data class BookedItem(
    val boardId: String,
    val syncId: String,
    val name: String,
    val description: String,
    val phones: List<String>,
    val expiresAt: LocalDateTime?,
    val startsAt: LocalDateTime?,
    val validated: Boolean,
)

/**
 * Citește tabelele, setările de rezervare și programările existente direct din
 * SharedPreferences-ul Flutter — folosit atât de MainActivity (afișarea „Spatiere”
 * pe Android) cât și de ClientBookingReceiver (botul SMS), ca să existe o singură
 * sursă de adevăr pentru calculul locurilor libere pe această platformă.
 */
object BookingSettings {
    private const val PREFS_NAME = "FlutterSharedPreferences"

    private val ISO_SHORT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // Citește un întreg indiferent dacă plugin-ul Flutter shared_preferences l-a
    // scris ca Int sau ca Long — versiuni diferite ale plugin-ului (mai ales cele
    // bazate pe noul backend Pigeon) scriu valorile int din Dart cu putLong(),
    // iar SharedPreferences.getInt() aruncă ClassCastException dacă tipul stocat
    // nu se potrivește exact. Number acoperă ambele cazuri fără să ghicim tipul.
    private fun getIntCompat(p: android.content.SharedPreferences, key: String, default: Int): Int =
        (p.all[key] as? Number)?.toInt() ?: default

    fun loadBoards(context: Context): List<BoardInfo> {
        val json = prefs(context).getString("flutter.management_boards", null) ?: return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.getJSONObject(i)
                val id = o.optString("id", "")
                if (id.isEmpty()) null else BoardInfo(id, o.optString("name", ""))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun loadSettings(context: Context, boardId: String): BoardBookingSettings {
        val p = prefs(context)
        val hoursStr = p.getString("flutter.work_hours_$boardId", null)
        val result = BoardBookingSettings(
            enabled = p.getBoolean("flutter.booking_enabled_$boardId", false),
            workHours = if (hoursStr != null) parseWorkHours(hoursStr) else legacyWorkHours(p, boardId),
            iban = p.getString("flutter.iban_$boardId", "") ?: "",
        )
        Diag.i("loadSettings: boardId=$boardId -> $result")
        return result
    }

    private val WORK_HOURS_ENTRY = Regex("""^(\d+):(\d+)-(\d+)$""")

    // „1:840-660,5:960-720” (zi:check-in-check-out) — scris de
    // encodeWorkHours din Dart; intrările invalide sunt sărite.
    fun parseWorkHours(raw: String): Map<Int, DayHours> {
        val result = mutableMapOf<Int, DayHours>()
        for (part in raw.split(",")) {
            val m = WORK_HOURS_ENTRY.matchEntire(part.trim()) ?: continue
            val day = m.groupValues[1].toIntOrNull() ?: continue
            val checkIn = m.groupValues[2].toIntOrNull() ?: continue
            val checkOut = m.groupValues[3].toIntOrNull() ?: continue
            if (day !in 1..7 || checkIn >= 24 * 60 || checkOut >= 24 * 60) continue
            result[day] = DayHours(checkIn, checkOut)
        }
        return result
    }

    // Setările salvate în formatul vechi (înainte de orele pe zile): aceleași
    // ore în toate zilele, mai puțin cele fără check-in.
    private fun legacyWorkHours(p: android.content.SharedPreferences, boardId: String): Map<Int, DayHours> {
        val closedStr = p.getString("flutter.closed_days_$boardId", "") ?: ""
        val closed = closedStr.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
        val hours = DayHours(
            getIntCompat(p, "flutter.work_start_$boardId", 14 * 60),
            getIntCompat(p, "flutter.work_end_$boardId", 11 * 60),
        )
        return (1..7).filter { it !in closed }.associateWith { hours }
    }

    // Cu câte minute înainte de expirare vine alerta — ultima valoare aleasă
    // în aplicație („Setează alertă”), aceeași regulă ca _loadAlertLead din Dart.
    const val DEFAULT_ALERT_LEAD_MIN = 60

    fun loadAlertLeadMin(context: Context, boardId: String): Int {
        val v = getIntCompat(prefs(context), "flutter.alert_lead_minutes_$boardId", 0)
        return if (v > 0) v else DEFAULT_ALERT_LEAD_MIN
    }

    private fun parseFlexibleIso(raw: String): LocalDateTime? = try {
        LocalDateTime.parse(raw)
    } catch (_: Exception) {
        try {
            LocalDateTime.parse(raw, ISO_SHORT)
        } catch (_: Exception) {
            null
        }
    }

    // Citește lista completă de înregistrări ale unui tabel (syncId, telefoane,
    // dată expirare) — folosit de fluxul de anulare prin SMS ca să găsească
    // programarea unui client după numărul de telefon, indiferent dacă a fost
    // creată de bot sau adăugată manual din aplicație.
    //
    // Include și rezervările din coada de sincronizare încă neprocesate de
    // Flutter (coada se golește doar când aplicația e deschisă/în prim-plan —
    // vezi loadZileBusyRanges) — altfel un client care trimite „anuleaza” la
    // câteva minute după ce a rezervat prin SMS, fără să fi fost deschisă
    // între timp aplicația, primește „nu am găsit nicio programare activă”,
    // deși rezervarea chiar există (doar că încă n-a ajuns în lista aplicată).
    fun loadBookedItems(context: Context, boardId: String): List<BookedItem> {
        // Cheie = syncId, ca o rezervare cu update în coadă (PEN:U:) să
        // înlocuiască versiunea persistată, nu să apară de două ori.
        val result = LinkedHashMap<String, BookedItem>()

        val itemsJson = prefs(context).getString("flutter.management_items_$boardId", null)
        if (itemsJson != null) {
            try {
                val arr = JSONArray(itemsJson)
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val syncId = o.optString("syncId", "")
                    if (syncId.isEmpty()) continue
                    val phones = listOfNotNull(
                        o.optString("phoneNumber", "").takeIf { it.isNotEmpty() },
                        o.optString("phoneNumber2", "").takeIf { it.isNotEmpty() },
                        o.optString("phoneNumber3", "").takeIf { it.isNotEmpty() },
                    )
                    if (phones.isEmpty()) continue
                    val expiresStr = o.optString("expiresAt", "")
                    val expiresAt = if (o.isNull("expiresAt") || expiresStr.isEmpty()) null else parseFlexibleIso(expiresStr)
                    val startsStr = o.optString("startsAt", "")
                    val startsAt = if (o.isNull("startsAt") || startsStr.isEmpty()) null else parseFlexibleIso(startsStr)
                    result[syncId] = BookedItem(
                        boardId = boardId,
                        syncId = syncId,
                        name = o.optString("name", ""),
                        description = o.optString("description", ""),
                        phones = phones,
                        expiresAt = expiresAt,
                        startsAt = startsAt,
                        validated = o.optBoolean("validated", false),
                    )
                }
            } catch (e: Exception) {
                Diag.e("loadBookedItems: JSON parse failed for boardId=$boardId", e)
            }
        }

        for ((prefix, payload) in queuedEntries(context, boardId)) {
            if (prefix == "PEN:D:") {
                // Ștergere încă neprocesată — nu o oferim la anulare.
                result.remove(payload.trim())
                continue
            }
            if (prefix !in ITEM_PREFIXES) continue
            val j = parsePayload(payload) ?: continue
            val syncId = j.optString("s", "")
            if (syncId.isEmpty()) continue
            val phones = listOfNotNull(
                j.optString("p1", "").takeIf { it.isNotEmpty() },
                j.optString("p2", "").takeIf { it.isNotEmpty() },
                j.optString("p3", "").takeIf { it.isNotEmpty() },
            )
            if (phones.isEmpty()) continue
            val expiresStr = j.optString("e", "")
            val startsStr = j.optString("st", "")
            result[syncId] = BookedItem(
                boardId = boardId,
                syncId = syncId,
                name = j.optString("n", ""),
                description = j.optString("d", ""),
                phones = phones,
                expiresAt = if (expiresStr.isEmpty()) null else parseFlexibleIso(expiresStr),
                startsAt = if (startsStr.isEmpty()) null else parseFlexibleIso(startsStr),
                validated = j.optBoolean("v", false),
            )
        }

        return result.values.toList()
    }

    // Intervalul ocupat al unui sejur = [startsAt, expiresAt) — durata nu e fixă
    // per tabel (clientul o alege prin SMS).
    // Sejururile fără startsAt (introduse manual, fără câmpul de check-in) sunt
    // aproximate la 1 noapte înainte de expiresAt, ca să nu fie ignorate din calcul.
    fun loadZileBusyRanges(context: Context, boardId: String): List<BusyInterval> {
        val p = prefs(context)
        val result = mutableListOf<BusyInterval>()

        val itemsJson = p.getString("flutter.management_items_$boardId", null)
        if (itemsJson != null) {
            try {
                val arr = JSONArray(itemsJson)
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val expiresStr = o.optString("expiresAt", "")
                    if (o.isNull("expiresAt") || expiresStr.isEmpty()) continue
                    val end = parseFlexibleIso(expiresStr) ?: continue
                    val startsStr = o.optString("startsAt", "")
                    val start = if (o.isNull("startsAt") || startsStr.isEmpty()) {
                        end.minusDays(1)
                    } else {
                        parseFlexibleIso(startsStr) ?: end.minusDays(1)
                    }
                    result.add(BusyInterval(start, end))
                }
            } catch (e: Exception) {
                Diag.e("loadZileBusyRanges: JSON parse failed for boardId=$boardId", e)
            }
        }

        // Rezervări deja confirmate de clienți, dar încă neprocesate de aplicație
        // (stau în coada de sincronizare) — trebuie tratate ca ocupate, altfel doi
        // clienți ar putea primi aceleași date înainte ca aplicația să fie
        // deschisă și coada procesată.
        for ((prefix, payload) in queuedEntries(context, boardId)) {
            if (prefix !in ITEM_PREFIXES) continue
            val j = parsePayload(payload) ?: continue
            val end = parseFlexibleIso(j.optString("e", "")) ?: continue
            val startsStr = j.optString("st", "")
            val start = if (startsStr.isEmpty()) end.minusDays(1) else (parseFlexibleIso(startsStr) ?: end.minusDays(1))
            result.add(BusyInterval(start, end))
        }

        return result
    }

    // Intrările din coada de sincronizare pentru un tabel, încă neprocesate de
    // Flutter, ca (prefix, payload). Fiecare intrare e citită separat — una
    // coruptă e sărită, fără să le ascundă pe cele de după ea (altfel o oră
    // deja rezervată ar fi oferită din nou).
    internal fun queuedEntries(context: Context, boardId: String): List<Pair<String, String>> {
        val queueJson = context
            .getSharedPreferences(SmsSyncReceiver.PREFS_NAME, Context.MODE_PRIVATE)
            .getString(SmsSyncReceiver.QUEUE_KEY, "[]") ?: "[]"
        val arr = try { JSONArray(queueJson) } catch (_: Exception) { return emptyList() }
        val result = mutableListOf<Pair<String, String>>()
        for (i in 0 until arr.length()) {
            val entry = arr.optJSONObject(i) ?: continue
            if (entry.optString("board", "") != boardId) continue
            val msg = entry.optString("msg", "")
            if (msg.length < 6 || !msg.startsWith("PEN:")) continue
            result.add(msg.substring(0, 6) to msg.substring(6))
        }
        return result
    }

    // Payload-ul JSON al unei intrări „PEN:A/I/U:”, sau null dacă e corupt.
    private fun parsePayload(payload: String): JSONObject? = try {
        JSONObject(payload)
    } catch (_: Exception) {
        Diag.w("queued sync entry skipped: invalid JSON")
        null
    }

    private val ITEM_PREFIXES = setOf("PEN:A:", "PEN:I:", "PEN:U:")
}
