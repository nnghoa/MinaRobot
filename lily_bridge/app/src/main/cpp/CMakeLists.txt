cmake_minimum_required(VERSION 3.18.1)
project("mina_kws_jni" C)

get_filename_component(MINA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
set(PREBUILT_ABI_DIR "${MINA_ROOT}/android/app/src/main/jniLibs/${ANDROID_ABI}")

add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION "${PREBUILT_ABI_DIR}/libonnxruntime.so"
)

add_library(sherpa-onnx-c-api SHARED IMPORTED)
set_target_properties(sherpa-onnx-c-api PROPERTIES
    IMPORTED_LOCATION "${PREBUILT_ABI_DIR}/libsherpa-onnx-c-api.so"
)

add_library(mina_kws_jni SHARED
    mina_kws_jni.c
)

target_include_directories(mina_kws_jni PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

find_library(log-lib log)

target_link_libraries(mina_kws_jni
    sherpa-onnx-c-api
    onnxruntime
    ${log-lib}
)
