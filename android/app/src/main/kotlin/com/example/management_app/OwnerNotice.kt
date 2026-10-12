package com.example.management_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.atomic.AtomicInteger

/**
 * Notificări pentru proprietar despre ce s-a întâmplat fără el: anulări
 * făcute de clienți prin SMS, anulări automate la 24h, backup automat eșuat.
 * Fără ele, proprietarul afla doar dacă observa că a dispărut un rând.
 */
object OwnerNotice {

    // Interval separat de ID-urile alarmelor (sub 100.000.000) și ale
    // reminderelor botului (900.000.000+).
    private const val ID_BASE = 950_000_000
    private val counter = AtomicInteger((System.currentTimeMillis() % 1_000_000).toInt())

    /** Canalul comun cu alertele programate (NotifAlarmReceiver). */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                NotifAlarmReceiver.CHANNEL_ID,
                tr("Alerte Rezervări Pensiune", "Rezervări Pensiune alerts"),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { enableVibration(true) }
        )
    }

    fun show(context: Context, title: String, body: String) {
        try {
            AppLang.sync(context)
            ensureChannel(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val iconRes = context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName)
            val icon = if (iconRes != 0) iconRes else android.R.drawable.ic_dialog_info
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, NotifAlarmReceiver.CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
            }
            builder.setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
            if (open != null) builder.setContentIntent(PendingIntent.getActivity(context, 0, open, flags))
            nm.notify(ID_BASE + counter.incrementAndGet() % 1_000_000, builder.build())
        } catch (e: Exception) {
            // Fără permisiunea de notificări (Android 13+) — nu blocăm restul.
            Diag.e("OwnerNotice failed", e)
        }
    }
}
