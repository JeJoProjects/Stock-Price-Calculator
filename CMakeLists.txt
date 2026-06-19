cmake_minimum_required(VERSION 3.20)
project(StockPriceCalculator LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(THIRD_PARTY_DIR "${CMAKE_SOURCE_DIR}/external")
set(IMGUI_DIR "${THIRD_PARTY_DIR}/imgui")
set(GLFW_DIR "${THIRD_PARTY_DIR}/glfw")

if(NOT EXISTS "${IMGUI_DIR}/imgui.cpp")
    message(FATAL_ERROR "Missing submodule: external/imgui. Run setup.bat to initialize submodules.")
endif()

if(NOT EXISTS "${GLFW_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Missing submodule: external/glfw. Run setup.bat to initialize submodules.")
endif()

set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
add_subdirectory(${GLFW_DIR} ${CMAKE_BINARY_DIR}/_deps/glfw EXCLUDE_FROM_ALL)
set(GLFW_TARGET glfw)

file(GLOB_RECURSE APP_SOURCES
    src/*.cpp
)

set(IMGUI_SOURCES
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_glfw.cpp
    ${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp
    ${IMGUI_DIR}/misc/cpp/imgui_stdlib.cpp
)

add_executable(${PROJECT_NAME} WIN32
    ${APP_SOURCES}
    ${IMGUI_SOURCES}
)

target_include_directories(${PROJECT_NAME} PRIVATE
    src
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
    ${IMGUI_DIR}/misc/cpp
    ${GLFW_DIR}/include
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    ${GLFW_TARGET}
    opengl32
    gdi32
    shell32
    dwmapi
    imm32
    winhttp
    crypt32
)

target_compile_options(${PROJECT_NAME} PRIVATE
    -Wall -Wextra -Wpedantic
)

file(COPY ${CMAKE_SOURCE_DIR}/data/us_tickers_full.json
     DESTINATION ${CMAKE_BINARY_DIR}/data)

add_executable(test_calc_engine
    src/core/calcEngine.cpp
    tests/testCalcEngine.cpp
)
target_include_directories(test_calc_engine PRIVATE src)
target_compile_options(test_calc_engine PRIVATE -Wall -Wextra -Wpedantic)
