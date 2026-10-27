package com.example.management_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.security.KeyFactory
import java.security.interfaces.RSAPublicKey
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** „Ospita” e un produs separat de Appunta. */
class AppIdentityTest {

    @Test
    fun `licenta are cheia proprie, nu pe cea a aplicației Appunta`() {
        // Fragment din cheia publică a aplicației Appunta.
        assertFalse(LicenseStore.PUBLIC_KEY_B64.contains("6LMDi/tUuBHqLag6NHTw"))
        val key = KeyFactory.getInstance("RSA").generatePublic(
            X509EncodedKeySpec(Base64.getDecoder().decode(LicenseStore.PUBLIC_KEY_B64))
        ) as RSAPublicKey
        assertEquals(2048, key.modulus.bitLength())
    }

    @Test
    fun `backup-urile si sincronizarea nu se confunda cu Appunta`() {
        assertEquals("pensiune", BackupFormat.APP_ID)
        assertEquals(".penbackup", BackupFormat.EXTENSION)
        assertEquals("PEN:", SmsSyncReceiver.SYNC_PREFIX)
        assertEquals("PEN:S:", SyncAuth.SIGNED_PREFIX)
    }
}
