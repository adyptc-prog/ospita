package com.example.management_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.time.LocalDateTime

/**
 * Se declanșează la 24h după o rezervare pe un tabel „zile” (pensiune) —
 * programată fie nativ (ClientBookingReceiver, la rezervare prin bot), fie
 * din Dart (ValidationService, la adăugare manuală din aplicație).
 *
 * Dacă rezervarea a fost între timp validată (plată confirmată) sau ștearsă,
 * nu face nimic. Altfel, o șterge din coada de sincronizare (la fel ca la
 * anularea prin SMS) și anunță clientul prin SMS.
 */
class ValidationDeadlineReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // ID-ul e String.hashCode() al syncId-ului — negativ în ~jumătate din
        // cazuri, deci nu se poate folosi -1 ca „lipsă”.
        if (!intent.hasExtra("validation_alarm_id")) return
        val alarmId = intent.getIntExtra("validation_alarm_id", 0)

        val pending = goAsync()
        val appContext = context.applicationContext
        Thread {
            try {
                handle(appContext, alarmId)
            } catch (e: Exception) {
                Diag.e("ValidationDeadlineReceiver: failed for alarmId=$alarmId", e)
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun handle(context: Context, alarmId: Int) {
        AppLang.sync(context)
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val dataStr = prefs.getString("flutter.validation_alarm_$alarmId", null) ?: return
        val data = JSONObject(dataStr)
        val boardId = data.optString("board", "")
        val syncId = data.optString("sync", "")
        if (boardId.isEmpty() || syncId.isEmpty()) return

        val item = BookingSettings.loadBookedItems(context, boardId).firstOrNull { it.syncId == syncId }
            ?: return // deja ștearsă (manual sau altfel) — nimic de făcut
        if (item.validated) return // plata a fost confirmată între timp
        // Sejurul a început deja (sau s-a încheiat): clientul e/a fost la
        // pensiune — nu anulăm și nu-i trimitem „anulată automat”.
        if (!stayIsInFuture(item, LocalDateTime.now())) return

        val boardName = BookingSettings.loadBoards(context).firstOrNull { it.id == boardId }?.name ?: ""
        SmsSyncReceiver.enqueueLocal(context, boardId, "PEN:D:$syncId")
        OwnerNotice.show(
            context, tr("Rezervare anulată automat", "Booking cancelled automatically"),
            tr(
                "${item.name} ($boardName) — plata nu a fost confirmată în 24 de ore.",
                "${item.name} ($boardName) — the payment was not confirmed within 24 hours.",
            ),
        )

        val phone = item.phones.firstOrNull() ?: return
        sendSmsNow(
            context, phone,
            tr(
                "Rezervarea ta la $boardName a fost anulată automat — plata nu a fost confirmată în cele 24 de ore.",
                "Your booking at $boardName was cancelled automatically — the payment was not confirmed within 24 hours.",
            )
        )
    }

    companion object {
        /** Check-in-ul (sau, fără el, check-out-ul) e încă în viitor. */
        internal fun stayIsInFuture(item: BookedItem, now: LocalDateTime): Boolean {
            val start = item.startsAt ?: item.expiresAt?.minusDays(1) ?: return true
            return start.isAfter(now)
        }
    }

    private fun sendSmsNow(context: Context, phone: String, message: String) {
        SmsSender.send(context, phone, message)
    }
}
