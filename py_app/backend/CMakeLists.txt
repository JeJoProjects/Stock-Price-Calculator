cmake_minimum_required(VERSION 3.20)
project(StockCalcEngine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(stockcalc_engine SHARED
    src/calc_engine.cpp
    src/exports.cpp
)

target_include_directories(stockcalc_engine PRIVATE include)

# Test executable
add_executable(test_calc_engine tests/test_calc.cpp src/calc_engine.cpp)
target_include_directories(test_calc_engine PRIVATE include)
