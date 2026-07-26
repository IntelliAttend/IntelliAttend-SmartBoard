cmake_minimum_required(VERSION 3.14)
project(bootstrapper LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(bootstrapper WIN32
  "main.cpp"
  "common.cpp"
  "logger.cpp"
  "installer.cpp"
  "dialog.cpp"
  "resources/bootstrapper.rc"
  "resources/bootstrapper.manifest"
)

target_compile_definitions(bootstrapper PRIVATE
  UNICODE
  _UNICODE
  NOMINMAX
)

if(MSVC)
  target_compile_options(bootstrapper PRIVATE /W4 /WX /EHsc /Zc:__cplusplus)
  target_compile_options(bootstrapper PRIVATE /MT$<$<CONFIG:Debug>:d>)
  target_link_options(bootstrapper PRIVATE /INCREMENTAL:NO /GUARD:CF /CETCOMPAT)
else()
  target_compile_options(bootstrapper PRIVATE -Wall -Wextra -Werror -O3 -municode)
  target_link_options(bootstrapper PRIVATE -municode -static -mwindows -s)
endif()

target_link_libraries(bootstrapper PRIVATE
  kernel32
  user32
  shell32
  shlwapi
  comctl32
  winhttp
)

target_include_directories(bootstrapper PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
