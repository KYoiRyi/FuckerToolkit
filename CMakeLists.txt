cmake_minimum_required(VERSION 3.20)

project(FuckerToolkit LANGUAGES CXX)

include(FetchContent)

option(FTK_WITH_LUA "Build with a system Lua 5.4 runtime" OFF)
option(FTK_BUILD_SHARED "Build the toolkit as a shared library" ON)
option(FTK_FETCH_MINHOOK "Fetch MinHook automatically on Windows" ON)
set(FTK_TINYHOOK_ROOT "" CACHE PATH "Path to a local tinyhook install or source checkout")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(FTK_LIBRARY_TYPE STATIC)
if(FTK_BUILD_SHARED)
  set(FTK_LIBRARY_TYPE SHARED)
endif()

add_library(ftk ${FTK_LIBRARY_TYPE}
  src/core/bootstrap.cpp
  src/lua/api_bridge.cpp
  src/lua/lua_context.cpp
  src/pal/memory_manager.cpp
  src/pal/path_resolver.cpp
  src/vfs/vfs.cpp
)

if(WIN32 AND FTK_BUILD_SHARED)
  set_target_properties(ftk PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()

target_include_directories(ftk
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_definitions(ftk PRIVATE FTK_PROJECT_NAME="FuckerToolkit")

if(WIN32)
  target_sources(ftk PRIVATE src/app_entry/windows_entry.cpp)
  target_compile_definitions(ftk PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_sources(ftk PRIVATE src/hook/minhook_engine.cpp)

  if(FTK_FETCH_MINHOOK)
    FetchContent_Declare(
      minhook
      GIT_REPOSITORY https://github.com/TsudaKageyu/minhook.git
      GIT_TAG v1.3.4
    )
    FetchContent_MakeAvailable(minhook)
    target_link_libraries(ftk PRIVATE minhook)
  else()
    find_package(minhook CONFIG REQUIRED)
    target_link_libraries(ftk PRIVATE minhook::minhook)
  endif()
elseif(ANDROID)
  target_sources(ftk PRIVATE src/app_entry/android_entry.cpp)
  target_sources(ftk PRIVATE src/hook/shadowhook_engine.cpp)
  find_package(shadowhook REQUIRED CONFIG)
  target_link_libraries(ftk PRIVATE shadowhook::shadowhook)
elseif(APPLE)
  target_sources(ftk PRIVATE src/app_entry/apple_entry.cpp)
  target_sources(ftk PRIVATE src/hook/tinyhook_engine.cpp)
  find_path(TINYHOOK_INCLUDE_DIR tinyhook.h
    HINTS
      ${FTK_TINYHOOK_ROOT}/include
      ${FTK_TINYHOOK_ROOT}
  )
  find_library(TINYHOOK_LIBRARY tinyhook
    HINTS
      ${FTK_TINYHOOK_ROOT}/lib
      ${FTK_TINYHOOK_ROOT}/build
      ${FTK_TINYHOOK_ROOT}
  )
  if(NOT TINYHOOK_INCLUDE_DIR OR NOT TINYHOOK_LIBRARY)
    message(FATAL_ERROR "tinyhook is required on Apple platforms. Set -DFTK_TINYHOOK_ROOT=/path/to/tinyhook or provide TINYHOOK_INCLUDE_DIR/TINYHOOK_LIBRARY.")
  endif()
  target_include_directories(ftk PRIVATE ${TINYHOOK_INCLUDE_DIR})
  target_link_libraries(ftk PRIVATE ${TINYHOOK_LIBRARY})
else()
  target_sources(ftk PRIVATE src/app_entry/posix_entry.cpp)
  message(FATAL_ERROR "No hook backend is configured for this platform.")
endif()

if(FTK_WITH_LUA)
  find_package(Lua 5.4 REQUIRED)
  target_link_libraries(ftk PRIVATE ${LUA_LIBRARIES})
  target_include_directories(ftk PRIVATE ${LUA_INCLUDE_DIR})
  target_compile_definitions(ftk PRIVATE FTK_WITH_LUA=1)
endif()

if(UNIX AND NOT APPLE)
  target_link_libraries(ftk PRIVATE dl pthread)
endif()

add_executable(ftk_smoke_test tests/smoke_main.cpp)
target_link_libraries(ftk_smoke_test PRIVATE ftk)
