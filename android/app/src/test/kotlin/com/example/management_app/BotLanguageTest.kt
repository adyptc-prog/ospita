package com.example.management_app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.LocalDateTime

/**
 * Botul răspunde în limba aleasă în aplicație pe telefonul care primește
 * SMS-ul, dar înțelege mereu cuvintele-cheie din ambele limbi.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BotLanguageTest {

    private lateinit var context: Context
    private val receiver = ClientBookingReceiver()
    private val client = "+40712345678"
    private val sent = mutableListOf<Pair<String, String>>()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString("flutter.management_boards",
                JSONArray().put(JSONObject().put("id", "b1").put("name", "Casa Ana")).toString())
            .putBoolean("flutter.booking_enabled_b1", true)
            .putLong("flutter.work_start_b1", 14L * 60)
            .putLong("flutter.work_end_b1", 11L * 60)
            .putString("flutter.management_items_b1", "[]")
            .commit()
        SmsSender.testSink = { phone, message -> sent.add(phone to message) }
    }

    @After
    fun tearDown() {
        SmsSender.testSink = null
        AppLang.setForTest(false)
    }

    private fun setAppLanguage(lang: String) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString(AppLang.PREF_KEY, lang).commit()
    }

    private fun say(text: String): String? {
        sent.clear()
        receiver.handleMessage(context, client, text)
        return sent.lastOrNull()?.second
    }

    @Test
    fun `aplicatia in engleza - fluxul complet raspunde in engleza`() {
        setAppLanguage("en")

        assertEquals("How many nights? Reply with a number (1-30).", say("free"))

        val offer = say("2")
        assertNotNull(offer)
        assertTrue(offer!!, offer.startsWith("Available, 2 nights at Casa Ana:\n1. "))
        assertTrue(offer, offer.contains("Reply with the option number to book"))

        val confirmation = say("1")
        assertNotNull(confirmation)
        assertTrue(confirmation!!, confirmation.startsWith("Your booking at Casa Ana, "))
        assertTrue(confirmation, confirmation.contains("(2 nights), has been saved. Pay within 24 hours"))

        val cancelled = say("cancel")
        assertNotNull(cancelled)
        assertTrue(cancelled!!, cancelled.startsWith("Your booking Casa Ana "))
        assertTrue(cancelled, cancelled.endsWith(" has been cancelled."))
    }

    @Test
    fun `aplicatia in engleza intelege si cuvintele romanesti`() {
        setAppLanguage("en")
        assertEquals("How many nights? Reply with a number (1-30).", say("Liber"))
        assertTrue(say("1 noapte")!!.startsWith("Available, 1 night at Casa Ana:"))
        say("1")
        assertTrue(say("anulează")!!.endsWith(" has been cancelled."))
    }

    @Test
    fun `aplicatia in romana intelege si cuvintele englezesti`() {
        setAppLanguage("ro")
        assertEquals("Câte nopți? Răspunde cu un număr (1-30).", say("FREE"))
        assertTrue(say("2 nights")!!.startsWith("Disponibil 2 nopți la Casa Ana:"))
        assertTrue(say("option 1")!!.startsWith("Rezervarea ta la Casa Ana, "))
        assertTrue(say("Cancel my booking")!!.endsWith(" a fost anulată."))
    }

    @Test
    fun `fara alegere in aplicatie botul foloseste limba telefonului`() {
        // Telefonul simulat e în română (build.gradle.kts).
        assertEquals("Câte nopți? Răspunde cu un număr (1-30).", say("free"))
    }

    @Test
    fun `ajutorul si mesajele de eroare sunt in limba aplicatiei`() {
        setAppLanguage("en")
        say("free")
        assertEquals(
            "I didn't understand. Reply with just the number of nights (e.g. 2).",
            say("hello there"),
        )
        assertEquals(
            "Invalid number of nights. Text FREE and then a number between 1 and 30.",
            say("45"),
        )
        assertEquals(
            "I couldn't find \"atlantida\". Check the name and text FREE again.",
            say("free atlantida"),
        )
        assertEquals("I found no active booking for this number.", say("cancel"))
    }

    @Test
    fun `un SMS personal in engleza ramane fara raspuns`() {
        setAppLanguage("en")
        assertEquals(null, say("are you free tonight for dinner?"))
        assertEquals(null, say("please cancel"))
        assertEquals(null, say("2"))
    }

    @Test
    fun `limba se schimba de la un mesaj la altul, dupa alegerea din aplicatie`() {
        setAppLanguage("ro")
        assertEquals("Câte nopți? Răspunde cu un număr (1-30).", say("liber"))
        setAppLanguage("en")
        assertTrue(say("2")!!.startsWith("Available, 2 nights at Casa Ana:"))
    }

    @Test
    fun `mesajul de reminder implicit urmeaza limba, cel editat ramane neatins`() {
        val at = LocalDateTime.of(2027, 3, 5, 11, 0)
        assertEquals(BotReminders.DEFAULT_TEMPLATE_RO, BotReminders.effectiveTemplate(null))
        assertEquals(BotReminders.DEFAULT_TEMPLATE_RO, BotReminders.effectiveTemplate(BotReminders.DEFAULT_TEMPLATE_EN))

        AppLang.setForTest(true)
        assertEquals(BotReminders.DEFAULT_TEMPLATE_EN, BotReminders.effectiveTemplate(null))
        assertEquals(BotReminders.DEFAULT_TEMPLATE_EN, BotReminders.effectiveTemplate(BotReminders.DEFAULT_TEMPLATE_RO))
        assertEquals("Textul meu [NUME]", BotReminders.effectiveTemplate("Textul meu [NUME]"))
        assertEquals(
            "Reminder: Ana. It expires on 05.03.2027 11:00. Please take the necessary steps.",
            BotReminders.buildMessage(BotReminders.effectiveTemplate(null), "Ana", at),
        )
        assertEquals(
            "Ana/Ana 05.03.2027 11:00/05.03.2027 11:00",
            BotReminders.buildMessage("[NUME]/[NAME] [DATA_EXPIRARE]/[EXPIRY_DATE]", "Ana", at),
        )
    }

    @Test
    fun `regula de limba - alegerea din aplicatie, altfel limba telefonului`() {
        assertTrue(AppLang.resolveIsEn("en", "ro"))
        assertFalse(AppLang.resolveIsEn("ro", "en"))
        assertFalse(AppLang.resolveIsEn(null, "ro"))
        assertTrue(AppLang.resolveIsEn(null, "en"))
        assertTrue(AppLang.resolveIsEn(null, "de"))
        assertFalse(BackupFormat.isBackedUpKey(AppLang.PREF_KEY))
    }
}
