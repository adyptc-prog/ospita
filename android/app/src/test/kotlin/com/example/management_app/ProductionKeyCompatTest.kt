package com.example.management_app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/**
 * Compatibilitatea site ↔ aplicație pe cheia de PRODUCȚIE: fixture-ul e semnat
 * cu cheia privată reală (tools/private.pem, aceeași din variabila Netlify
 * LICENSE_PRIVATE_KEY_PEM_PENSIUNE) prin lib/licenseSigner.js din
 * voltacademy_web. E o licență expirată (ianuarie 2026), verificată „la data”
 * de 15 ianuarie 2026 — nu poate activa nimic în realitate.
 */
class ProductionKeyCompatTest {

    private val license = JSONObject(
        javaClass.classLoader!!.getResource("production_key_fixture.json")!!.readText()
    ).getJSONObject("license")
    private val decoder: (String) -> ByteArray = { Base64.getMimeDecoder().decode(it) }
    private val verifier = LicenseVerifier(decoder(LicenseStore.PUBLIC_KEY_B64), decoder)
    private val jan15 = LicenseVerifier.parseIso8601Utc("2026-01-15T00:00:00Z")!!

    @Test
    fun `licenta semnata de site cu cheia de productie e acceptata de aplicatie`() {
        val r = verifier.evaluate(license.toString(), "pensiune-1700000000000", jan15)
        assertTrue(r.message, r.isActive)
    }

    @Test
    fun `semnatura nu se potriveste daca e modificata licenta`() {
        val tampered = JSONObject(license.toString())
        tampered.getJSONObject("payload").put("validUntil", "2099-01-01T00:00:00Z")
        val r = verifier.evaluate(tampered.toString(), "pensiune-1700000000000", jan15)
        assertEquals("Semnătura licenței nu este validă.", r.message)
    }

    @Test
    fun `licenta de test e expirata azi`() {
        val r = verifier.evaluate(license.toString(), "pensiune-1700000000000", System.currentTimeMillis())
        assertEquals("Licența a expirat.", r.message)
    }
}
