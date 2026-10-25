package com.hermes.hermes_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps a call with Frank alive while Frank is in the background or the
 * phone is locked. Android lets an app use the mic off screen only from a
 * foreground service; this is it, shown as an ongoing "Call with Hermsy"
 * notification with a running clock and an End call button.
 */
class CallService : Service() {
    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_END) {
            onEndFromNotification?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Hermsy"
        val notification = notification(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // The screen may go off mid-sentence; the call must not sleep with it.
        if (wake == null) {
            wake = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "frank:call")
                .apply { acquire(4 * 60 * 60 * 1000L) }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Frank was swiped away: the call went with it.
        stopSelf()
    }

    override fun onDestroy() {
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        super.onDestroy()
    }

    private fun notification(title: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Calls", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while you are on a call with Hermsy"
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val end = PendingIntent.getService(
            this,
            1,
            Intent(this, CallService::class.java).setAction(ACTION_END),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        fun builder() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        // On a locked phone: that there is a call, not which chat it is in.
        val public = builder()
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentTitle("Call with Hermsy")
            .setUsesChronometer(true)
            .setWhen(System.currentTimeMillis())
            .build()
        return builder()
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentTitle("Call with Hermsy")
            .setContentText(title)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setWhen(System.currentTimeMillis())
            .setContentIntent(open)
            .addAction(
                Notification.Action.Builder(null, "End call", end).build(),
            )
            .build()
    }

    companion object {
        const val NOTIFICATION_ID = 7301
        const val CHANNEL = "frank_calls"
        const val ACTION_END = "com.hermes.hermes_app.END_CALL"
        const val EXTRA_TITLE = "title"

        /** Set by MainActivity: tells Dart the call was ended from here. */
        var onEndFromNotification: (() -> Unit)? = null

        fun start(context: Context, title: String) {
            val intent = Intent(context, CallService::class.java).putExtra(EXTRA_TITLE, title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallService::class.java))
        }
    }
}
