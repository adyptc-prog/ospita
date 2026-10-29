package com.example.management_app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ClientBookingReceiverTest {

    private lateinit var context: Context
    private val receiver = ClientBookingReceiver()
    private val client = "+40712345678"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString("flutter.management_boards",
                JSONArray().put(JSONObject().put("id", "b1").put("name", "Salon Ana")).toString())
            .putBoolean("flutter.booking_enabled_b1", true)
            .putLong("flutter.work_start_b1", 14L * 60) // check-in
            .putLong("flutter.work_end_b1", 11L * 60)   // check-out
            .putString("flutter.management_items_b1", "[]")
            .commit()
        SmsSender.testSink = { phone, message -> sent.add(phone to message) }
    }

    private val sent = mutableListOf<Pair<String, String>>()

    @After
    fun tearDown() {
        SmsSender.testSink = null
    }

    private fun clearSent() = sent.clear()

    // Textul ultimului SMS trimis de bot, sau null dacă n-a trimis nimic.
    private fun lastSent(): String? = sent.lastOrNull()?.second

    private fun queueFutureBooking(syncId: String, daysAhead: Long) {
        val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
        val start = LocalDateTime.now().plusDays(daysAhead).withHour(14).withMinute(0)
        val end = start.plusDays(1).withHour(11)
        val payload = JSONObject().put("s", syncId).put("n", client)
            .put("c", LocalDateTime.now().format(fmt)).put("st", start.format(fmt))
            .put("e", end.format(fmt)).put("p1", client)
        SmsSyncReceiver.enqueue(context, "b1", "PEN:A:$payload")
    }

    @Test
    fun `raspunde la LIBER de la un numar de telefon`() {
        receiver.handleMessage(context, client, "liber")
        val sent = lastSent()
        assertNotNull(sent)
        assertTrue(sent!!.startsWith("Câte nopți?"))
    }

    @Test
    fun `fluxul complet - nopti, date disponibile, rezervare cu termen de plata`() {
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "2")
        assertTrue(lastSent()!!.startsWith("Disponibil 2 nopți la Salon Ana"))
        receiver.handleMessage(context, client, "1")
        assertTrue(lastSent()!!.startsWith("Rezervarea ta la Salon Ana"))
        assertTrue(lastSent()!!.contains("Achită în maxim 24 de ore"))

        val payload = JSONObject(
            JSONArray(SmsSyncReceiver.snapshot(context)).getJSONObject(0)
                .getString("msg").removePrefix("PEN:A:")
        )
        assertTrue(payload.has("st")) // check-in
        // Termenul de plată de 24h a fost programat nativ.
        val alarmId = AlarmScheduler.validationAlarmId(payload.getString("s"))
        assertTrue(
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .contains("flutter.validation_alarm_$alarmId")
        )
    }

    @Test
    fun `botul nu trimite SMS partenerului, rezervarea ramane de trimis de aplicatie`() {
        // Play Protect: SMS primit → SMS imediat către alt număr = tipar de troian.
        val partner = "+40799999999"
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString("flutter.sync_partner_phone_b1", partner)
            .putString("flutter.sync_secret_b1", "K7QM2XPA")
            .commit()
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "2")
        receiver.handleMessage(context, client, "1")

        val entry = JSONArray(SmsSyncReceiver.snapshot(context)).getJSONObject(0)
        assertFalse(entry.optBoolean("forwarded"))
        assertTrue(sent.none { it.first == partner })
    }

    @Test
    fun `fara partener rezervarea ramane de trimis de aplicatie`() {
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "2")
        receiver.handleMessage(context, client, "1")

        val entry = JSONArray(SmsSyncReceiver.snapshot(context)).getJSONObject(0)
        assertFalse(entry.optBoolean("forwarded"))
    }

    @Test
    fun `anularea prin SMS il anunta pe proprietar`() {
        queueFutureBooking("anul1", daysAhead = 5)
        receiver.handleMessage(context, client, "anuleaza")

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val titles = org.robolectric.Shadows.shadowOf(nm).allNotifications
            .map { it.extras.getString(android.app.Notification.EXTRA_TITLE) }
        assertEquals(listOf("Rezervare anulată de client"), titles)
    }

    @Test
    fun `un numar fara lista activa e un SMS personal - fara raspuns`() {
        receiver.handleMessage(context, client, "2")
        receiver.handleMessage(context, client, "10")
        assertNull(lastSent())
    }

    @Test
    fun `raspunsul cu numar dupa expirarea listei primeste explicatia`() {
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "2")
        // Lista de date a expirat (peste 20 de minute), dar e din aceeași zi.
        val prefs = context.getSharedPreferences("ClientBookingPrefs", Context.MODE_PRIVATE)
        val offers = JSONObject(prefs.getString("offers", "{}")!!)
        val key = offers.keys().next()
        offers.getJSONObject(key).put("ts", System.currentTimeMillis() - 60 * 60_000L)
        prefs.edit().putString("offers", offers.toString()).commit()
        clearSent()

        receiver.handleMessage(context, client, "1")
        assertTrue(lastSent()!!.startsWith("Nu am nicio ofertă activă"))
    }

    @Test
    fun `nu raspunde expeditorilor alfanumerici sau numerelor scurte`() {
        receiver.handleMessage(context, "BancaX", "liber")
        receiver.handleMessage(context, "1234", "liber")
        assertNull(lastSent())
    }

    @Test
    fun `peste limita pe ora vine o singura explicatie, apoi botul tace`() {
        repeat(BotLimits.MAX_COMMANDS_PER_NUMBER_PER_HOUR) {
            clearSent()
            receiver.handleMessage(context, client, "liber")
            assertNotNull(lastSent())
        }
        clearSent()
        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Ai trimis multe mesaje"))
        assertTrue(Regex("după ora \\d{2}:\\d{2}").containsMatchIn(lastSent()!!))
        clearSent()
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "3")
        assertNull(lastSent())
    }

    @Test
    fun `al doilea LIBER porneste o lista noua, iar alegerea merge pe ea`() {
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "liber")
        clearSent()
        receiver.handleMessage(context, client, "2")
        assertTrue(lastSent()!!.startsWith("Disponibil 2 nopți"))
    }

    @Test
    fun `cu lista activa sunt acceptate si forme ca 3 punct sau optiunea 3`() {
        for (text in listOf("2.", "opțiunea 2", "Nr. 2", "2)")) {
            context.getSharedPreferences("ClientBookingPrefs", Context.MODE_PRIVATE).edit().clear().commit()
            SmsSyncReceiver.acknowledge(context,
                (0 until JSONArray(SmsSyncReceiver.snapshot(context)).length()).map {
                    JSONArray(SmsSyncReceiver.snapshot(context)).getJSONObject(it).getString("id")
                })
            receiver.handleMessage(context, client, "liber")
            receiver.handleMessage(context, client, "1")
            clearSent()
            receiver.handleMessage(context, client, text)
            assertTrue("„$text”: ${lastSent()}", lastSent()!!.startsWith("Rezervarea ta la Salon Ana"))
        }
    }

    @Test
    fun `la intrebarea Cate nopti se accepta si 2 nopti`() {
        for (text in listOf("2 nopți", "2 nopti", "2 zile", "2.")) {
            context.getSharedPreferences("ClientBookingPrefs", Context.MODE_PRIVATE).edit().clear().commit()
            receiver.handleMessage(context, client, "liber")
            clearSent()
            receiver.handleMessage(context, client, text)
            assertTrue("„$text”: ${lastSent()}", lastSent()!!.startsWith("Disponibil 2 nopți"))
        }
    }

    @Test
    fun `fara lista activa formele libere sunt ignorate`() {
        receiver.handleMessage(context, client, "opțiunea 2")
        receiver.handleMessage(context, client, "2.")
        assertNull(lastSent())
    }

    @Test
    fun `text nerecunoscut cu lista activa primeste ajutor o singura data`() {
        receiver.handleMessage(context, client, "liber")
        clearSent()
        receiver.handleMessage(context, client, "de vineri până duminică")
        assertTrue(lastSent()!!.startsWith("Nu am înțeles. Răspunde doar cu numărul de nopți"))
        clearSent()
        receiver.handleMessage(context, client, "alo?")
        assertNull(lastSent())
        // La lista de date, alt ajutor.
        receiver.handleMessage(context, client, "1")
        clearSent()
        receiver.handleMessage(context, client, "vreau weekendul")
        assertTrue(lastSent()!!.startsWith("Nu am înțeles. Răspunde doar cu numărul variantei"))
        clearSent()
        receiver.handleMessage(context, client, "alo?")
        assertNull(lastSent())
        // O listă nouă poate primi din nou ajutor.
        receiver.handleMessage(context, client, "liber")
        clearSent()
        receiver.handleMessage(context, client, "alo?")
        assertNotNull(lastSent())
    }

    @Test
    fun `mesajele lungi nu primesc ajutor nici cu lista activa`() {
        receiver.handleMessage(context, client, "liber")
        clearSent()
        receiver.handleMessage(context, client,
            "Salut, ne vedem diseară la cină? Adu te rog și cartea pe care ți-am împrumutat-o.")
        assertNull(lastSent())
    }

    @Test
    fun `textele obisnuite nu consuma din limita`() {
        repeat(30) { receiver.handleMessage(context, client, "salut, ce faci?") }
        receiver.handleMessage(context, client, "liber")
        assertNotNull(lastSent())
    }

    @Test
    fun `cu 2 rezervari active nu se mai ofera ore`() {
        queueFutureBooking("r1", 1)
        queueFutureBooking("r2", 2)

        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Ai deja 2 rezervări active"))
    }

    @Test
    fun `a doua rezervare activa e permisa, a treia nu`() {
        queueFutureBooking("r1", 20)
        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Câte nopți?"))
        receiver.handleMessage(context, client, "1")
        receiver.handleMessage(context, client, "1")
        assertTrue(lastSent()!!.startsWith("Rezervarea ta"))

        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Ai deja 2 rezervări active"))
    }

    @Test
    fun `tabelul necunoscut nu dezvaluie numele tabelelor`() {
        receiver.handleMessage(context, client, "liber xyz")
        val sent = lastSent()!!
        assertTrue(sent.startsWith("Nu am găsit tabelul"))
        assertFalse(sent.contains("Salon Ana"))
    }

    @Test
    fun `numaratoarea zilnica e salvata`() {
        receiver.handleMessage(context, client, "liber")
        val state = JSONObject(
            context.getSharedPreferences("ClientBookingPrefs", Context.MODE_PRIVATE)
                .getString("rateLimits", "{}")!!
        )
        assertEquals(1, state.getInt("dayCount"))
    }

    @Test
    fun `rezervarea facuta de bot e marcata (fara SMS EXPIRAT)`() {
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "1")
        receiver.handleMessage(context, client, "1")
        val arr = JSONArray(SmsSyncReceiver.snapshot(context))
        val msg = arr.getJSONObject(0).getString("msg")
        assertTrue(msg.startsWith("PEN:A:"))
        assertEquals(true, JSONObject(msg.removePrefix("PEN:A:")).getBoolean("b"))
    }

    private fun lastQueued(): JSONObject {
        val arr = JSONArray(SmsSyncReceiver.snapshot(context))
        return JSONObject(arr.getJSONObject(arr.length() - 1).getString("msg").removePrefix("PEN:A:"))
    }

    @Test
    fun `rezervarea facuta de bot primeste alerta inainte de sosire`() {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putLong("flutter.alert_lead_minutes_b1", 1440L).commit()
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "1")
        receiver.handleMessage(context, client, "3")
        val j = lastQueued()
        val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
        val start = LocalDateTime.parse(j.getString("st"), fmt)
        val w = start.minusDays(1)
        if (w.isAfter(LocalDateTime.now())) assertEquals(w.format(fmt), j.getString("w"))
        else assertFalse(j.has("w"))
    }

    private fun setNoShows(count: Int, threshold: Int? = null) {
        val dates = JSONArray()
        repeat(count) { dates.put(LocalDateTime.now().minusDays(it + 1L).toString()) }
        val e = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString("flutter.no_show_summary", JSONObject().put("712345678", dates).toString())
        if (threshold != null) e.putLong("flutter.no_show_block_threshold", threshold.toLong())
        e.commit()
    }

    @Test
    fun `clientul cu 3 neprezentari e refuzat o data, apoi botul tace`() {
        setNoShows(3)
        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Nu mai poți face rezervări prin SMS"))
        clearSent()
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "1")
        assertNull(lastSent())
    }

    @Test
    fun `neconfirmatele de peste 24 de ore blocheaza si cu aplicatia inchisa`() {
        setNoShows(2)
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString("flutter.no_show_pending", JSONObject().put("712345678",
                JSONArray().put(LocalDateTime.now().minusHours(30).toString())).toString())
            .commit()
        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Nu mai poți face rezervări prin SMS"))
    }

    @Test
    fun `clientul blocat isi poate anula programarea`() {
        queueFutureBooking("r1", 1)
        setNoShows(3)
        receiver.handleMessage(context, client, "anuleaza")
        assertTrue(lastSent()!!.contains("a fost anulată"))
    }

    @Test
    fun `cu o neprezentare sub prag clientul e avertizat la confirmare`() {
        setNoShows(2)
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "1")
        receiver.handleMessage(context, client, "1")
        assertTrue(lastSent()!!.contains("Atenție: ai 2 neprezentări. La 3 nu mai poți rezerva prin SMS."))
    }

    @Test
    fun `pragul ales in aplicatie e respectat, iar 0 dezactiveaza blocarea`() {
        setNoShows(2, threshold = 2)
        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Nu mai poți face rezervări prin SMS"))

        context.getSharedPreferences("ClientBookingPrefs", Context.MODE_PRIVATE).edit().clear().commit()
        setNoShows(5, threshold = 0)
        clearSent()
        receiver.handleMessage(context, client, "liber")
        assertTrue(lastSent()!!.startsWith("Câte nopți?"))
    }

    @Test
    fun `fara interval salvat alerta e cu o ora inainte de sosire`() {
        assertEquals(60, BookingSettings.loadAlertLeadMin(context, "b1"))
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "1")
        receiver.handleMessage(context, client, "3")
        val j = lastQueued()
        val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm")
        val start = LocalDateTime.parse(j.getString("st"), fmt)
        assertEquals(start.minusMinutes(60).format(fmt), j.getString("w"))
    }
}

