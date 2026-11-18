package com.mtc.minalilybridge

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.ubtrobot.Robot
import com.ubtrobot.async.Cancelable
import com.ubtrobot.locomotion.LocomotionManager
import com.ubtrobot.locomotion.LocomotionOption
import com.ubtrobot.sensor.SensorDevice
import com.ubtrobot.sensor.SensorEvent
import com.ubtrobot.sensor.SensorListener
import com.ubtrobot.sensor.SensorManager
import com.ubtrobot.servo.RotationOption
import com.ubtrobot.servo.ServoManager

/**
 * Điều khiển bánh xe (LocomotionManager) và servo cổ (ServoManager) trên robot UBTECH Visbot
 * qua bộ SDK nội bộ com.ubtrobot.* kết nối với Master_Rosa.
 */
object VisbotMotorController {
    private const val TAG = "MinaBridgeMotor"

    @Volatile
    var isInitialized: Boolean = false
        private set

    var lastStatusMessage: String = "Chưa khởi tạo"
        private set

    private var locomotionManager: LocomotionManager? = null
    private var servoManager: ServoManager? = null
    private var sensorManager: SensorManager? = null
    private var sensorsRegistered: Boolean = false
    private var lastSensorPressMs: Long = 0L
    private var currentLocomotionPromise: Cancelable? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    var onFrontSensorPressed: ((String) -> Unit)? = null

    fun init(context: Context) {
        if (isInitialized && locomotionManager != null) return
        try {
            val appCtx = context.applicationContext
            Robot.initialize(appCtx)
            val global = Robot.globalContext()
            locomotionManager = global.getSystemService("locomotion") as? LocomotionManager
            servoManager = global.getSystemService("servo") as? ServoManager
            sensorManager = global.getSystemService("sensor") as? SensorManager
            registerPhysicalButtonSensors()
            isInitialized = (locomotionManager != null || servoManager != null)
            lastStatusMessage = "ROSA OK (loco=${locomotionManager != null}, servo=${servoManager != null})"
            Log.i(TAG, lastStatusMessage)
        } catch (e: Throwable) {
            isInitialized = false
            lastStatusMessage = "Lỗi khởi tạo ROSA: ${e.message}"
            Log.e(TAG, lastStatusMessage, e)
        }
    }

    private fun registerPhysicalButtonSensors() {
        if (sensorsRegistered) return
        val sm = sensorManager ?: return
        try {
            val devices = sm.deviceList ?: emptyList()
            for (dev in devices) {
                val id = dev.id ?: continue
                val meta = "${dev.id} ${dev.name ?: ""} ${dev.type ?: ""} ${dev.description ?: ""}".lowercase()
                val isButtonOrTouch = (meta.contains("button") || meta.contains("touch") || meta.contains("key") || meta.contains("tap") || meta.contains("pat")) &&
                    !meta.contains("pir") && !meta.contains("ir") && !meta.contains("infra") &&
                    !meta.contains("cliff") && !meta.contains("sonar") && !meta.contains("ultra") &&
                    !meta.contains("battery") && !meta.contains("drop")
                if (isButtonOrTouch) {
                    try { sm.enable(id) } catch (_: Throwable) {}
                    sm.registerListener(id, object : SensorListener {
                        override fun onSensorChanged(device: SensorDevice?, event: SensorEvent?) {
                            val v = event?.values?.firstOrNull() ?: 0f
                            if (v >= 1.0f) {
                                val now = System.currentTimeMillis()
                                if (now - lastSensorPressMs >= 700L) {
                                    lastSensorPressMs = now
                                    onFrontSensorPressed?.invoke(id)
                                }
                            }
                        }
                    })
                }
            }
            sensorsRegistered = true
        } catch (_: Throwable) {
        }
    }

    fun move(direction: String, durationMs: Long = 1200L, customSpeed: Float? = null): String {
        val dir = direction.trim().lowercase()
        if (dir == "stop") return stop()
        if (dir == "dance") return dance()

        val loco = locomotionManager
            ?: return "LocomotionManager chưa sẵn sàng ($lastStatusMessage)"

        val dur = durationMs.coerceIn(200L, 10000L)
        return try {
            stopInternal()
            val builder = LocomotionOption.Builder().setDuration(dur)
            val desc = when (dir) {
                "forward", "tien" -> {
                    builder.setMovingSpeed((customSpeed ?: 15f).coerceIn(5f, 40f))
                    "tiến lên (${dur}ms)"
                }
                "backward", "back", "lui" -> {
                    builder.setMovingSpeed(-(customSpeed ?: 15f).coerceIn(5f, 40f))
                    "lùi lại (${dur}ms)"
                }
                "turn_left", "left", "trai" -> {
                    builder.setTurningSpeed((customSpeed ?: 200f).coerceIn(40f, 360f))
                    "quay trái (${dur}ms)"
                }
                "turn_right", "right", "phai" -> {
                    builder.setTurningSpeed(-(customSpeed ?: 200f).coerceIn(40f, 360f))
                    "quay phải (${dur}ms)"
                }
                else -> return "Hướng không hợp lệ: $direction"
            }
            currentLocomotionPromise = loco.locomote(builder.build())
            "Đã điều khiển robot $desc"
        } catch (e: Throwable) {
            Log.e(TAG, "move($dir) error", e)
            "Lỗi bánh xe: ${e.message}"
        }
    }

    fun head(action: String, customAngle: Float? = null, customSpeed: Float? = null): String {
        val act = action.trim().lowercase()
        if (act == "nod" || act == "gat") {
            val r1 = rotateHead(20f, customSpeed ?: 32f)
            mainHandler.postDelayed({ rotateHead(-12f, 32f) }, 420L)
            mainHandler.postDelayed({ rotateHead(0f, 26f) }, 900L)
            return "$r1 (gật đầu)"
        }
        val targetAngle = when (act) {
            "up", "len", "ngua" -> -23f
            "down", "xuong", "cui" -> 25f
            "center", "giua", "ngang" -> 0f
            else -> (customAngle ?: 0f).coerceIn(-23f, 25f)
        }
        return rotateHead(targetAngle, customSpeed ?: 26f)
    }

    private fun rotateHead(angle: Float, speed: Float): String {
        val srv = servoManager ?: return "ServoManager chưa sẵn sàng ($lastStatusMessage)"
        val clampedAngle = angle.coerceIn(-23f, 25f)
        val clampedSpeed = speed.coerceIn(5f, 80f)
        return try {
            val opt = RotationOption.Builder("head")
                .setAngleAbsolute(true)
                .setAngle(clampedAngle)
                .setSpeed(clampedSpeed)
                .build()
            srv.rotate(opt)
            "Đã xoay đầu ${clampedAngle.toInt()}°"
        } catch (e: Throwable) {
            Log.e(TAG, "rotateHead error", e)
            "Lỗi cổ: ${e.message}"
        }
    }

    fun dance(): String {
        if (!isInitialized) return "ROSA chưa sẵn sàng"
        move("turn_left", 850L, 220f)
        rotateHead(-18f, 35f)
        mainHandler.postDelayed({
            move("turn_right", 1700L, 220f)
            rotateHead(20f, 35f)
        }, 900L)
        mainHandler.postDelayed({
            move("turn_left", 850L, 220f)
            rotateHead(-14f, 35f)
        }, 2700L)
        mainHandler.postDelayed({
            rotateHead(0f, 25f)
        }, 3650L)
        return "Robot đang nhảy múa!"
    }

    fun stop(): String {
        stopInternal()
        return "Đã dừng bánh xe."
    }

    private fun stopInternal() {
        try { currentLocomotionPromise?.cancel() } catch (_: Throwable) {}
        currentLocomotionPromise = null
    }
}
