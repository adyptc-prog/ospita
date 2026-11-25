package com.example.management_app

import android.app.AlarmManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.LocalDateTime

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BotRemindersTest {

    private lateinit var context: Context
    private val receiver = ClientBookingReceiver()
    private val client = "+40712345678"
    private val sent = mutableListOf<Pair<String, String>>()

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
            // Alerta cu 1 min înainte de sosire: prima dată liberă e în
            // viitor, deci și alerta.
            .putLong("flutter.alert_lead_minutes_b1", 1L)
            .putString("flutter.sms_template", "Salut [NUME], ne vedem la [DATA_EXPIRARE]")
            .commit()
        SmsSender.testSink = { phone, message -> sent.add(phone to message) }
    }

    @After
    fun tearDown() {
        SmsSender.testSink = null
    }

    private fun alarmManager() =
        shadowOf(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)

    // Doar alarmele de SMS — rezervarea pensiunii are și termenul de validare.
    private fun smsAlarms() = alarmManager().scheduledAlarms.filter {
        it.operation?.let { op -> shadowOf(op).savedIntent.component?.className } ==
            SmsAlarmReceiver::class.java.name
    }

    private fun book(): Pair<String, String> {
        receiver.handleMessage(context, client, "liber")
        receiver.handleMessage(context, client, "1") // o noapte
        receiver.handleMessage(context, client, "2") // a doua dată liberă
        val entry = JSONArray(SmsSyncReceiver.snapshot(context)).getJSONObject(0)
        val syncId = JSONObject(entry.getString("msg").removePrefix("PEN:A:")).getString("s")
        return entry.getString("id") to syncId
    }

    private fun reminderId(): Int = BotReminders.ID_BASE + 1

    @Test
    fun `rezervarea prin bot programeaza imediat reminderul provizoriu`() {
        book()
        val payload = BotReminders.payload(context, reminderId())
        assertNotNull(payload)
        assertEquals(client, payload!!.getString("phone"))
        assertTrue(payload.getString("message").startsWith("Salut $client, ne vedem la "))
        assertEquals(1, smsAlarms().size)
    }

    @Test
    fun `preluarea in aplicatie anuleaza reminderul provizoriu`() {
        val (entryId, _) = book()
        SmsSyncReceiver.acknowledge(context, listOf(entryId))
        assertNull(BotReminders.payload(context, reminderId()))
        assertTrue(smsAlarms().isEmpty())
    }

    @Test
    fun `anularea de catre client anuleaza reminderul provizoriu`() {
        book()
        receiver.handleMessage(context, client, "anuleaza")
        assertNull(BotReminders.payload(context, reminderId()))
        assertTrue(smsAlarms().isEmpty())
    }

    @Test
    fun `alarma provizorie trimite SMS-ul salvat`() {
        book()
        SmsAlarmReceiver().onReceive(context,
            android.content.Intent().putExtra("sms_alarm_id", reminderId()))
        // Receiverul trimite pe un fir separat.
        val deadline = System.currentTimeMillis() + 5_000
        while (sent.none { it.second.startsWith("Salut") } && System.currentTimeMillis() < deadline) {
            Thread.sleep(20)
        }
        assertTrue(sent.any { it.first == client && it.second.startsWith("Salut $client") })
    }

    @Test
    fun `dupa repornire reminderul e rearmat`() {
        book()
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        smsAlarms().forEach { a -> a.operation?.let { am.cancel(it) } }
        assertTrue(smsAlarms().isEmpty())
        AlarmRescheduler.rescheduleAll(context)
        assertEquals(1, smsAlarms().size)
    }

    @Test
    fun `id-urile provizorii nu se suprapun cu cele din Dart`() {
        // Dart: tabel*10.000.000 + număr*100 + 22, maxim 10 tabele.
        assertFalse(BotReminders.isBotReminderId(9 * 10_000_000 + 99_999 * 100 + 22))
        assertTrue(BotReminders.isBotReminderId(BotReminders.ID_BASE))
    }

    @Test
    fun `mesajul foloseste formatul de data al aplicatiei`() {
        assertEquals("X 0712 05.01.2030 10:30",
            BotReminders.buildMessage("X [NUME] [DATA_CHECKIN]", "0712",
                LocalDateTime.of(2030, 1, 5, 10, 30), LocalDateTime.of(2030, 1, 7, 11, 0)))
    }
}
