#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <android/log.h>
#include "c-api.h"

#define LOG_TAG "MinaKwsJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

typedef struct MinaKwsHandle {
    const SherpaOnnxKeywordSpotter *spotter;
    const SherpaOnnxOnlineStream *stream;
} MinaKwsHandle;

JNIEXPORT jlong JNICALL
Java_com_mtc_minalilybridge_MinaKwsNative_nativeCreate(
    JNIEnv *env,
    jobject thiz,
    jstring jEncoder,
    jstring jDecoder,
    jstring jJoiner,
    jstring jTokens,
    jstring jKeywords,
    jfloat keywordsScore,
    jfloat keywordsThreshold
) {
    const char *encoder = (*env)->GetStringUTFChars(env, jEncoder, NULL);
    const char *decoder = (*env)->GetStringUTFChars(env, jDecoder, NULL);
    const char *joiner = (*env)->GetStringUTFChars(env, jJoiner, NULL);
    const char *tokens = (*env)->GetStringUTFChars(env, jTokens, NULL);
    const char *keywords = (*env)->GetStringUTFChars(env, jKeywords, NULL);

    SherpaOnnxKeywordSpotterConfig config;
    memset(&config, 0, sizeof(config));

    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;

    config.model_config.transducer.encoder = encoder;
    config.model_config.transducer.decoder = decoder;
    config.model_config.transducer.joiner = joiner;
    config.model_config.tokens = tokens;
    config.model_config.num_threads = 1;
    config.model_config.provider = "cpu";
    config.model_config.debug = 0;

    config.max_active_paths = 4;
    config.num_trailing_blanks = 1;
    config.keywords_score = keywordsScore;
    config.keywords_threshold = keywordsThreshold;
    config.keywords_file = keywords;

    const SherpaOnnxKeywordSpotter *spotter = SherpaOnnxCreateKeywordSpotter(&config);

    (*env)->ReleaseStringUTFChars(env, jEncoder, encoder);
    (*env)->ReleaseStringUTFChars(env, jDecoder, decoder);
    (*env)->ReleaseStringUTFChars(env, jJoiner, joiner);
    (*env)->ReleaseStringUTFChars(env, jTokens, tokens);
    (*env)->ReleaseStringUTFChars(env, jKeywords, keywords);

    if (!spotter) {
        LOGE("SherpaOnnxCreateKeywordSpotter returned NULL");
        return 0L;
    }

    const SherpaOnnxOnlineStream *stream = SherpaOnnxCreateKeywordStream(spotter);
    if (!stream) {
        LOGE("SherpaOnnxCreateKeywordStream returned NULL");
        SherpaOnnxDestroyKeywordSpotter(spotter);
        return 0L;
    }

    MinaKwsHandle *h = (MinaKwsHandle *)calloc(1, sizeof(MinaKwsHandle));
    if (!h) {
        SherpaOnnxDestroyOnlineStream(stream);
        SherpaOnnxDestroyKeywordSpotter(spotter);
        return 0L;
    }
    h->spotter = spotter;
    h->stream = stream;
    LOGI("MinaKwsHandle created (score=%.2f, threshold=%.2f)", keywordsScore, keywordsThreshold);
    return (jlong)(intptr_t)h;
}

JNIEXPORT jstring JNICALL
Java_com_mtc_minalilybridge_MinaKwsNative_nativeAcceptAndDecode(
    JNIEnv *env,
    jobject thiz,
    jlong ptr,
    jshortArray jPcm,
    jint sampleCount
) {
    MinaKwsHandle *h = (MinaKwsHandle *)(intptr_t)ptr;
    if (!h || !h->spotter || !h->stream || sampleCount <= 0) {
        return (*env)->NewStringUTF(env, "");
    }

    jshort *pcm = (*env)->GetShortArrayElements(env, jPcm, NULL);
    if (!pcm) {
        return (*env)->NewStringUTF(env, "");
    }

    float *samples = (float *)malloc((size_t)sampleCount * sizeof(float));
    if (!samples) {
        (*env)->ReleaseShortArrayElements(env, jPcm, pcm, JNI_ABORT);
        return (*env)->NewStringUTF(env, "");
    }

    for (int i = 0; i < sampleCount; ++i) {
        samples[i] = ((float)pcm[i]) / 32768.0f;
    }
    (*env)->ReleaseShortArrayElements(env, jPcm, pcm, JNI_ABORT);

    SherpaOnnxOnlineStreamAcceptWaveform(h->stream, 16000, samples, sampleCount);
    free(samples);

    while (SherpaOnnxIsKeywordStreamReady(h->spotter, h->stream)) {
        SherpaOnnxDecodeKeywordStream(h->spotter, h->stream);
    }

    const SherpaOnnxKeywordResult *res = SherpaOnnxGetKeywordResult(h->spotter, h->stream);
    jstring jOut;
    if (res && res->keyword && res->keyword[0] != '\0') {
        LOGI("Detected keyword: %s", res->keyword);
        jOut = (*env)->NewStringUTF(env, res->keyword);
        SherpaOnnxResetKeywordStream(h->spotter, h->stream);
    } else {
        jOut = (*env)->NewStringUTF(env, "");
    }
    if (res) {
        SherpaOnnxDestroyKeywordResult(res);
    }
    return jOut;
}

JNIEXPORT void JNICALL
Java_com_mtc_minalilybridge_MinaKwsNative_nativeReset(
    JNIEnv *env,
    jobject thiz,
    jlong ptr
) {
    MinaKwsHandle *h = (MinaKwsHandle *)(intptr_t)ptr;
    if (h && h->spotter && h->stream) {
        SherpaOnnxResetKeywordStream(h->spotter, h->stream);
    }
}

JNIEXPORT void JNICALL
Java_com_mtc_minalilybridge_MinaKwsNative_nativeDestroy(
    JNIEnv *env,
    jobject thiz,
    jlong ptr
) {
    MinaKwsHandle *h = (MinaKwsHandle *)(intptr_t)ptr;
    if (!h) return;
    if (h->stream) {
        SherpaOnnxDestroyOnlineStream(h->stream);
        h->stream = NULL;
    }
    if (h->spotter) {
        SherpaOnnxDestroyKeywordSpotter(h->spotter);
        h->spotter = NULL;
    }
    free(h);
    LOGI("MinaKwsHandle destroyed");
}
