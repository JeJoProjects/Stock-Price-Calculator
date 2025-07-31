cmake_minimum_required(VERSION 3.6.0)
project(StockPriceCalculator)

# Add Unicode support
add_definitions(-DUNICODE -D_UNICODE)

file(GLOB SOURCES
    *.h
    *.hpp
    *.cc
    *.cpp
)

set(CMAKE_C_STANDARD 20)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

enable_testing()
add_executable(${PROJECT_NAME} WIN32 ${SOURCES})  # Added WIN32 here
set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT ${PROJECT_NAME})