cmake_minimum_required(VERSION 3.14)
project(update_agent LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(update_agent WIN32
  "main.cpp"
  "json_reader.cpp"
  "logger.cpp"
  "checksum.cpp"
  "file_utils.cpp"
  "process_watcher.cpp"
  "installer.cpp"
  "version_checker.cpp"
  "launcher.cpp"
  "heartbeat.cpp"
  "install_journal.cpp"
  "authenticode.cpp"
  "session.cpp"
  "event_log.cpp"
  "resources/update_agent.rc"
)

target_compile_definitions(update_agent PRIVATE
  UNICODE
  _UNICODE
  NOMINMAX
)

if(MSVC)
  target_compile_options(update_agent PRIVATE /W4 /WX /EHsc /Zc:__cplusplus)
  target_compile_options(update_agent PRIVATE /MT$<$<CONFIG:Debug>:d>)
  target_link_options(update_agent PRIVATE /INCREMENTAL:NO)
endif()

target_link_libraries(update_agent PRIVATE
  kernel32
  advapi32
  user32
  version
  crypt32
  shlwapi
  wtsapi32
)

target_include_directories(update_agent PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
