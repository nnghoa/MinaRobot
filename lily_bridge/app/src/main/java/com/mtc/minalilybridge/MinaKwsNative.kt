package com.mtc.minalilybridge

object MinaKwsNative {
    var loadError: String? = null
        private set

    val isLoaded: Boolean
        get() = loadError == null

    init {
        try {
            // Nạp tuần tự theo thứ tự phụ thuộc cho trình liên kết động Android 8.1 (Bionic)
            System.loadLibrary("onnxruntime")
            System.loadLibrary("sherpa-onnx-c-api")
            System.loadLibrary("mina_kws_jni")
        } catch (t: Throwable) {
            loadError = t.message ?: t.toString()
        }
    }

    external fun nativeCreate(
        encoderPath: String,
        decoderPath: String,
        joinerPath: String,
        tokensPath: String,
        keywordsPath: String,
        keywordsScore: Float,
        keywordsThreshold: Float
    ): Long

    external fun nativeAcceptAndDecode(
        handle: Long,
        pcm16: ShortArray,
        sampleCount: Int
    ): String

    external fun nativeReset(handle: Long)

    external fun nativeDestroy(handle: Long)
}
