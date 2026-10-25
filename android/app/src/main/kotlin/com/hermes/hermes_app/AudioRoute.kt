package com.hermes.hermes_app

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Where a call's voice goes in and out. A connected headset (Bluetooth or
 * wired) carries both ways; with none, the call is on the loudspeaker.
 * Dictation uses a headset's mic when there is one and leaves the phone
 * alone otherwise.
 *
 * The route is re-picked as headsets come and go, and put back if anything
 * else in the app (the audio plugins set the speakerphone themselves)
 * moves it while Frank holds it.
 */
class AudioRoute(context: Context, private val channel: MethodChannel) {
    private val appContext = context.applicationContext
    private val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())

    /** "call" or "dictation" while Frank holds the route, else null. */
    private var purpose: String? = null
    private var wanted: AudioDeviceInfo? = null
    private var previousMode = AudioManager.MODE_NORMAL
    private var listening = false

    /**
     * A begin() waiting for its device to go live. Bluetooth takes a moment
     * (often a second or two) to switch to its call link; sound played
     * before then comes out of the phone instead.
     */
    private var ready: ((Map<String, Any?>) -> Unit)? = null
    private var readyRoute: Map<String, Any?>? = null
    private val giveUp = Runnable { settle() }

    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = repick()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = repick()
    }

    private val changed = AudioManager.OnCommunicationDeviceChangedListener { device ->
        val want = wanted ?: return@OnCommunicationDeviceChangedListener
        if (purpose == null) {
            return@OnCommunicationDeviceChangedListener
        }
        if (device?.id == want.id) {
            settle()
        } else if (isAvailable(want)) {
            main.post { apply(want) }
        }
    }

    /**
     * Takes the route for [purpose] and calls [done] with what it picked
     * (see [describe]) once that device is live, or after 3 seconds.
     */
    fun begin(purpose: String, done: (Map<String, Any?>) -> Unit) {
        if (this.purpose == null) {
            previousMode = audio.mode
        }
        this.purpose = purpose
        if (!listening) {
            audio.registerAudioDeviceCallback(devices, main)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.addOnCommunicationDeviceChangedListener(appContext.mainExecutor, changed)
            }
            listening = true
        }
        settle()
        val picked = route()
        val want = wanted
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            want == null ||
            audio.communicationDevice?.id == want.id
        ) {
            done(picked)
            return
        }
        ready = done
        readyRoute = picked
        main.postDelayed(giveUp, 3000)
    }

    /** Answers a begin() still waiting. */
    private fun settle() {
        val callback = ready ?: return
        ready = null
        main.removeCallbacks(giveUp)
        callback(readyRoute ?: describe(wanted))
    }

    /** Lets go if Frank still holds the route for [purpose]. */
    fun end(purpose: String) {
        if (this.purpose != purpose) {
            return
        }
        settle()
        this.purpose = null
        wanted = null
        if (listening) {
            audio.unregisterAudioDeviceCallback(devices)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.removeOnCommunicationDeviceChangedListener(changed)
            }
            listening = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audio.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            run {
                audio.stopBluetoothSco()
                audio.isBluetoothScoOn = false
                audio.isSpeakerphoneOn = false
            }
        }
        audio.mode = previousMode
    }

    private fun repick() {
        if (purpose == null) {
            return
        }
        val now = route()
        channel.invokeMethod("routeChanged", now)
    }

    private fun route(): Map<String, Any?> {
        val headset = headset()
        val device = when {
            headset != null -> headset
            // Dictation without a headset: the phone's own mic, as before.
            purpose == "dictation" -> null
            else -> speaker()
        }
        wanted = device
        if (device == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.clearCommunicationDevice()
            }
            audio.mode = previousMode
            return describe(null)
        }
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        apply(device)
        return describe(device)
    }

    private fun apply(device: AudioDeviceInfo) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audio.setCommunicationDevice(device)
            return
        }
        @Suppress("DEPRECATION")
        when (device.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> {
                audio.isSpeakerphoneOn = false
                audio.startBluetoothSco()
                audio.isBluetoothScoOn = true
            }
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> {
                audio.stopBluetoothSco()
                audio.isSpeakerphoneOn = true
            }
            else -> {
                // A wired headset takes over by itself once nothing forces
                // the speaker or Bluetooth.
                audio.stopBluetoothSco()
                audio.isSpeakerphoneOn = false
            }
        }
    }

    private fun candidates(): List<AudioDeviceInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audio.availableCommunicationDevices
        } else {
            audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        }

    private fun isAvailable(device: AudioDeviceInfo) =
        candidates().any { it.id == device.id }

    /** The best headset: Bluetooth first (the one you just put on), then wired. */
    private fun headset(): AudioDeviceInfo? {
        val all = candidates()
        for (type in HEADSETS) {
            all.firstOrNull { it.type == type }?.let { return it }
        }
        return null
    }

    private fun speaker(): AudioDeviceInfo? =
        candidates().firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }

    private fun describe(device: AudioDeviceInfo?): Map<String, Any?> {
        val kind = when (device?.type) {
            null -> "phone"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET -> "wired"
            else -> "bluetooth"
        }
        val name = device?.productName?.toString()?.takeIf {
            kind == "bluetooth" && it.isNotBlank()
        }
        return mapOf("kind" to kind, "name" to name)
    }

    companion object {
        private val HEADSETS = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(AudioDeviceInfo.TYPE_BLE_HEADSET)
            }
            add(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                add(AudioDeviceInfo.TYPE_HEARING_AID)
            }
            add(AudioDeviceInfo.TYPE_WIRED_HEADSET)
            add(AudioDeviceInfo.TYPE_USB_HEADSET)
            add(AudioDeviceInfo.TYPE_WIRED_HEADPHONES)
        }
    }
}
