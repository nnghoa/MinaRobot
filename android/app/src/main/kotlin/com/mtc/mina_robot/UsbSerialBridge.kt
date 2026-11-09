package com.mtc.mina_robot

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Cổng serial qua USB OTG (CP2102 / CH340 / FTDI / PL2303) để điện thoại Android
 * nói chuyện với mạch MR-C3024FX của Robonova-II ở 9600 8N1.
 * Dùng API USB Host chính thức của Android (không cần root); lần đầu Android sẽ hỏi quyền.
 *
 * Sự kiện gửi lên Flutter qua EventChannel:
 *  - {"type":"data","bytes":ByteArray}
 *  - {"type":"status","open":Boolean,"name":String,"message":String}
 */
class UsbSerialBridge(private val context: Context) {
    companion object {
        private const val ACTION_USB_PERMISSION = "com.mtc.mina_robot.USB_PERMISSION"
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var port: UsbSerialPort? = null
    private var ioManager: SerialInputOutputManager? = null
    private var sink: EventChannel.EventSink? = null
    private var wantOpen = false
    private var baudRate = 9600
    private var pendingOpenResult: MethodChannel.Result? = null

    val isOpen: Boolean get() = port != null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val result = pendingOpenResult
                    pendingOpenResult = null
                    if (granted) {
                        val ok = openInternal()
                        result?.success(ok)
                    } else {
                        emitStatus("Người dùng chưa cho phép truy cập USB")
                        result?.success(false)
                    }
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    if (wantOpen && port == null) {
                        mainHandler.postDelayed({ open(baudRate, null) }, 500)
                    }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val dev: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    val cur = port?.driver?.device
                    if (cur != null && dev != null && dev.deviceId == cur.deviceId) {
                        closeInternal()
                        emitStatus("Đã rút cáp USB-serial")
                    }
                }
            }
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    fun setEventSink(s: EventChannel.EventSink?) {
        sink = s
        if (s != null) emitStatus(if (isOpen) "Đã kết nối" else "Chưa kết nối")
    }

    /** Danh sách thiết bị USB-serial đang cắm, dạng "Tên (VID:PID)". */
    fun listDevices(): List<String> {
        return UsbSerialProber.getDefaultProber().findAllDrivers(usbManager).map {
            val d = it.device
            "${it.javaClass.simpleName.removeSuffix("SerialDriver")} " +
                "(%04X:%04X)".format(d.vendorId, d.productId)
        }
    }

    /** Mở cổng USB-serial đầu tiên tìm thấy. Nếu chưa có quyền sẽ hỏi người dùng, kết quả trả về sau. */
    fun open(baud: Int, result: MethodChannel.Result?) {
        wantOpen = true
        baudRate = baud
        if (port != null) {
            try {
                port?.setParameters(baudRate, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            } catch (_: Throwable) {
            }
            result?.success(true)
            return
        }
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        if (drivers.isEmpty()) {
            emitStatus("Không thấy mạch USB-serial (CP2102/CH340). Kiểm tra cáp OTG.")
            result?.success(false)
            return
        }
        val device = drivers[0].device
        if (!usbManager.hasPermission(device)) {
            pendingOpenResult?.success(false)
            pendingOpenResult = result
            var flags = 0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
            val pi = PendingIntent.getBroadcast(
                context, 0, Intent(ACTION_USB_PERMISSION).setPackage(context.packageName), flags
            )
            usbManager.requestPermission(device, pi)
            emitStatus("Đang xin quyền USB, hãy bấm Cho phép trên màn hình")
            return
        }
        result?.success(openInternal())
    }

    private fun openInternal(): Boolean {
        closeInternal()
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        if (drivers.isEmpty()) return false
        val driver = drivers[0]
        val connection = usbManager.openDevice(driver.device)
        if (connection == null) {
            emitStatus("Không mở được thiết bị USB (thiếu quyền?)")
            return false
        }
        return try {
            val p = driver.ports[0]
            p.open(connection)
            p.setParameters(baudRate, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            try {
                p.dtr = true
                p.rts = true
            } catch (_: Throwable) {
            }
            port = p
            val mgr = SerialInputOutputManager(p, object : SerialInputOutputManager.Listener {
                override fun onNewData(data: ByteArray) {
                    val copy = data.copyOf()
                    mainHandler.post { sink?.success(mapOf("type" to "data", "bytes" to copy)) }
                }

                override fun onRunError(e: Exception) {
                    mainHandler.post {
                        // Bỏ qua lỗi của cổng đã chủ động đóng
                        if (port !== p) return@post
                        closeInternal()
                        emitStatus("Mất kết nối USB-serial: ${e.message}")
                    }
                }
            })
            ioManager = mgr
            mgr.start()
            emitStatus("Đã kết nối ${driver.javaClass.simpleName.removeSuffix("SerialDriver")} @ $baudRate")
            true
        } catch (e: Throwable) {
            closeInternal()
            emitStatus("Lỗi mở cổng USB-serial: ${e.message}")
            false
        }
    }

    fun write(bytes: ByteArray): Boolean {
        val p = port ?: return false
        return try {
            p.write(bytes, 200)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun close() {
        wantOpen = false
        closeInternal()
        emitStatus("Đã đóng cổng USB-serial")
    }

    private fun closeInternal() {
        try {
            ioManager?.stop()
        } catch (_: Throwable) {
        }
        ioManager = null
        try {
            port?.close()
        } catch (_: Throwable) {
        }
        port = null
    }

    private fun emitStatus(message: String) {
        val name = port?.driver?.javaClass?.simpleName?.removeSuffix("SerialDriver") ?: ""
        val evt = mapOf("type" to "status", "open" to isOpen, "name" to name, "message" to message)
        if (Looper.myLooper() == Looper.getMainLooper()) sink?.success(evt) else mainHandler.post { sink?.success(evt) }
    }

    fun dispose() {
        close()
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Throwable) {
        }
    }
}
