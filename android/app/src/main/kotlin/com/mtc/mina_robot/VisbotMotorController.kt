package com.mtc.mina_robot

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
 * thông qua bộ SDK nội bộ com.ubtrobot.* kết nối với MasterProvider (content://com.ubtrobot.provider.master).
 */
object VisbotMotorController {
    private const val TAG = "VisbotMotor"

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

    /** Gọi khi nút bấm / cảm ứng chạm vật lý trên thân Visbot được kích hoạt */
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
            lastStatusMessage = "UBTECH SDK OK (loco=${locomotionManager != null}, servo=${servoManager != null}, sensor=${sensorManager != null})"
            Log.i(TAG, lastStatusMessage)
        } catch (e: Throwable) {
            isInitialized = false
            lastStatusMessage = "Lỗi khởi tạo UBTECH SDK: ${e.message}"
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
                Log.i(TAG, "UBTECH Sensor device: id=$id, type=${dev.type}, name=${dev.name}, desc=${dev.description}")
                val isButtonOrTouch = (meta.contains("button") || meta.contains("touch") || meta.contains("key") || meta.contains("tap") || meta.contains("pat")) &&
                    !meta.contains("pir") && !meta.contains("ir") && !meta.contains("infra") &&
                    !meta.contains("cliff") && !meta.contains("sonar") && !meta.contains("ultra") &&
                    !meta.contains("battery") && !meta.contains("drop")
                if (isButtonOrTouch) {
                    try {
                        sm.enable(id)
                    } catch (_: Throwable) {
                    }
                    sm.registerListener(id, object : SensorListener {
                        override fun onSensorChanged(device: SensorDevice?, event: SensorEvent?) {
                            val v = event?.values?.firstOrNull() ?: 0f
                            if (v >= 1.0f) {
                                val now = System.currentTimeMillis()
                                if (now - lastSensorPressMs >= 600L) {
                                    lastSensorPressMs = now
                                    Log.i(TAG, "Physical button/touch sensor pressed: id=$id, v=$v")
                                    onFrontSensorPressed?.invoke(id)
                                }
                            }
                        }
                    })
                }
            }
            sensorsRegistered = true
        } catch (e: Throwable) {
            Log.w(TAG, "Không đọc được danh sách cảm biến Visbot: ${e.message}")
        }
    }

    /**
     * Điều khiển bánh xe:
     * - forward: tiến thẳng (movingSpeed = +15f)
     * - backward: lùi lại (movingSpeed = -15f)
     * - turn_left / left / spin_left: quay trái (turningSpeed = +200f)
     * - turn_right / right / spin_right: quay phải (turningSpeed = -200f)
     * - stop: dừng ngay lập tức
     */
    fun move(direction: String, durationMs: Long = 1500L, customSpeed: Float? = null): String {
        val dir = direction.trim().lowercase()
        if (dir == "stop") {
            return stop()
        }
        if (dir == "dance") {
            return dance()
        }

        val loco = locomotionManager
            ?: return "Lỗi: Dịch vụ LocomotionManager chưa sẵn sàng ($lastStatusMessage)"

        val dur = durationMs.coerceIn(200L, 10000L)
        return try {
            stopInternal()
            val builder = LocomotionOption.Builder().setDuration(dur)
            val desc = when (dir) {
                "forward", "tien" -> {
                    val spd = (customSpeed ?: 15f).coerceIn(5f, 40f)
                    builder.setMovingSpeed(spd)
                    "tiến lên (${dur}ms)"
                }
                "backward", "back", "lui" -> {
                    val spd = (customSpeed ?: 15f).coerceIn(5f, 40f)
                    builder.setMovingSpeed(-spd)
                    "lùi lại (${dur}ms)"
                }
                "turn_left", "left", "spin_left", "spinleft", "turnleft", "rotateleft", "trai" -> {
                    val spd = (customSpeed ?: 200f).coerceIn(40f, 360f)
                    builder.setTurningSpeed(spd)
                    "quay trái (${dur}ms)"
                }
                "turn_right", "right", "spin_right", "spinright", "turnright", "rotateright", "phai" -> {
                    val spd = (customSpeed ?: 200f).coerceIn(40f, 360f)
                    builder.setTurningSpeed(-spd)
                    "quay phải (${dur}ms)"
                }
                else -> return "Hướng không hợp lệ: $direction"
            }

            currentLocomotionPromise = loco.locomote(builder.build())
            "Đã điều khiển robot $desc"
        } catch (e: Throwable) {
            Log.e(TAG, "move($dir) failed", e)
            "Lỗi điều khiển bánh xe: ${e.message}"
        }
    }

    /**
     * Điều khiển servo cổ ("head"):
     * Góc tuyệt đối của Visbot: -23° (ngẩng lên tối đa) .. 0° (nhìn thẳng) .. +25° (cúi xuống tối đa).
     */
    fun head(action: String, customAngle: Float? = null, customSpeed: Float? = null): String {
        val act = action.trim().lowercase()
        if (act == "nod" || act == "gat") {
            val r1 = rotateHead(22f, customSpeed ?: 30f)
            mainHandler.postDelayed({
                rotateHead(-12f, 30f)
            }, 450L)
            mainHandler.postDelayed({
                rotateHead(0f, 25f)
            }, 950L)
            return "$r1 (gật đầu)"
        }

        val targetAngle = when (act) {
            "up", "head_up", "headup", "len", "ngua" -> -23f
            "down", "head_down", "headdown", "xuong", "cui" -> 25f
            "center", "head_center", "giua", "ngang" -> 0f
            else -> (customAngle ?: 0f).coerceIn(-23f, 25f)
        }
        return rotateHead(targetAngle, customSpeed ?: 25f)
    }

    private fun rotateHead(angle: Float, speed: Float): String {
        val srv = servoManager
            ?: return "Lỗi: Dịch vụ ServoManager chưa sẵn sàng ($lastStatusMessage)"
        val clampedAngle = angle.coerceIn(-23f, 25f)
        val clampedSpeed = speed.coerceIn(5f, 80f)
        return try {
            val opt = RotationOption.Builder("head")
                .setAngleAbsolute(true)
                .setAngle(clampedAngle)
                .setSpeed(clampedSpeed)
                .build()
            srv.rotate(opt)
            "Đã xoay đầu tới góc ${clampedAngle.toInt()}°"
        } catch (e: Throwable) {
            Log.e(TAG, "rotateHead($clampedAngle) failed", e)
            "Lỗi điều khiển đầu: ${e.message}"
        }
    }

    /**
     * Điệu nhảy vui nhộn kết hợp xoay bánh xe và gật đầu.
     */
    fun dance(): String {
        if (!isInitialized) return "Robot chưa sẵn sàng ($lastStatusMessage)"
        move("turn_left", 900L, 220f)
        rotateHead(-18f, 35f)
        mainHandler.postDelayed({
            move("turn_right", 1800L, 220f)
            rotateHead(20f, 35f)
        }, 950L)
        mainHandler.postDelayed({
            move("turn_left", 900L, 220f)
            rotateHead(-15f, 35f)
        }, 2800L)
        mainHandler.postDelayed({
            rotateHead(0f, 25f)
        }, 3800L)
        return "Robot đang nhảy múa!"
    }

    fun stop(): String {
        stopInternal()
        return "Đã dừng bánh xe."
    }

    private fun stopInternal() {
        try {
            currentLocomotionPromise?.cancel()
        } catch (_: Throwable) {
        }
        currentLocomotionPromise = null
    }
}
