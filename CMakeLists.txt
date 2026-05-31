cmake_minimum_required(VERSION 3.20)
project(StockPriceCalculator LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(IMGUI_DIR "D:/C++/External Libraries/IMGUI")
set(GLFW_DIR  "D:/C++/External Libraries/glfw-3.4.bin.WIN64")

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

target_link_directories(${PROJECT_NAME} PRIVATE
    ${GLFW_DIR}/lib-mingw-w64
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    glfw3
    opengl32
    gdi32
    shell32
    dwmapi
    imm32
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
