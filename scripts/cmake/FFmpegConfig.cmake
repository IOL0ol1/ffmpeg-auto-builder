# CMake package for an ffmpeg-auto-builder package, installed as lib/cmake/FFmpeg/.
#
#   find_package(FFmpeg REQUIRED [COMPONENTS avcodec avformat ...])
#   target_link_libraries(app PRIVATE FFmpeg::avformat)   # or FFmpeg::FFmpeg for everything
#
# Defines FFmpeg::<component> for every FFmpeg library in the package. Dependencies between
# the libraries and, for static libraries, the other libraries they need come from the
# package's pkg-config files. Set FFmpeg_USE_STATIC_LIBS to prefer static libraries when
# the package has both.
cmake_minimum_required(VERSION 3.13)

get_filename_component(_ffmpeg_prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(FFmpeg_INCLUDE_DIRS "${_ffmpeg_prefix}/include")
set(FFmpeg_LIBRARIES "")

# "Requires:" / "Requires.private:" entries (libavutil >= 61.0.100, ...) -> component names.
# Shared builds list the other FFmpeg libraries as private; linking them as well lets code
# use every library it depends on.
function(_ffmpeg_pc_requires component out)
  set(names "")
  file(STRINGS "${_ffmpeg_prefix}/lib/pkgconfig/lib${component}.pc" lines REGEX "^Requires(\\.private)?:")
  foreach(line IN LISTS lines)
    string(REGEX MATCHALL "lib[a-z0-9_]+" matches "${line}")
    foreach(match IN LISTS matches)
      string(REGEX REPLACE "^lib" "" name "${match}")
      list(APPEND names "${name}")
    endforeach()
  endforeach()
  set(${out} "${names}" PARENT_SCOPE)
endfunction()

# Link items of a static library besides itself ("-lx264", "-framework CoreVideo", ...).
function(_ffmpeg_pc_libs component out)
  set(items "")
  file(STRINGS "${_ffmpeg_prefix}/lib/pkgconfig/lib${component}.pc" lines REGEX "^Libs(\\.private)?:")
  foreach(line IN LISTS lines)
    string(REGEX REPLACE "^Libs(\\.private)?: *" "" line "${line}")
    separate_arguments(tokens UNIX_COMMAND "${line}")
    set(framework FALSE)
    foreach(token IN LISTS tokens)
      if(framework)
        list(APPEND items "-framework ${token}")
        set(framework FALSE)
      elseif(token STREQUAL "-framework")
        set(framework TRUE)
      elseif(NOT token MATCHES "^-L" AND NOT token STREQUAL "-l${component}")
        list(APPEND items "${token}")
      endif()
    endforeach()
  endforeach()
  list(REMOVE_DUPLICATES items)
  set(${out} "${items}" PARENT_SCOPE)
endfunction()

function(_ffmpeg_add component)
  if(TARGET FFmpeg::${component})
    return()
  endif()
  set(pc "${_ffmpeg_prefix}/lib/pkgconfig/lib${component}.pc")
  if(NOT EXISTS "${pc}")
    return()
  endif()

  set(dir "${_ffmpeg_prefix}/lib")
  file(GLOB dll "${_ffmpeg_prefix}/bin/${component}-[0-9]*.dll")
  set(static "")
  foreach(candidate "${dir}/lib${component}.a" "${dir}/${component}.lib" "${dir}/lib${component}.lib")
    if(EXISTS "${candidate}" AND NOT (dll AND candidate MATCHES "/${component}\\.lib$"))
      set(static "${candidate}")
      break()
    endif()
  endforeach()
  set(shared "")
  foreach(candidate "${dir}/lib${component}.dylib" "${dir}/lib${component}.so")
    if(EXISTS "${candidate}")
      set(shared "${candidate}")
      break()
    endif()
  endforeach()

  _ffmpeg_pc_requires(${component} requires)
  foreach(dependency IN LISTS requires)
    _ffmpeg_add(${dependency})
  endforeach()
  list(TRANSFORM requires PREPEND "FFmpeg::")

  if(dll AND EXISTS "${dir}/${component}.lib" AND NOT (FFmpeg_USE_STATIC_LIBS AND static))
    # Windows shared: import library plus DLL.
    add_library(FFmpeg::${component} SHARED IMPORTED)
    list(GET dll 0 dll)
    set_target_properties(FFmpeg::${component} PROPERTIES
      IMPORTED_IMPLIB "${dir}/${component}.lib" IMPORTED_LOCATION "${dll}")
  elseif(shared AND NOT (FFmpeg_USE_STATIC_LIBS AND static))
    add_library(FFmpeg::${component} SHARED IMPORTED)
    set_target_properties(FFmpeg::${component} PROPERTIES IMPORTED_LOCATION "${shared}")
  elseif(static)
    add_library(FFmpeg::${component} STATIC IMPORTED)
    set_target_properties(FFmpeg::${component} PROPERTIES IMPORTED_LOCATION "${static}")
    # The third-party static libraries are in the same lib/ directory.
    _ffmpeg_pc_libs(${component} libs)
    list(APPEND requires ${libs})
    set_property(TARGET FFmpeg::${component} APPEND PROPERTY INTERFACE_LINK_DIRECTORIES "${dir}")
  else()
    return()
  endif()
  set_target_properties(FFmpeg::${component} PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${FFmpeg_INCLUDE_DIRS}"
    INTERFACE_LINK_LIBRARIES "${requires}"
    # FFmpeg's headers use INT64_C and friends, which C++ only defines with this macro.
    INTERFACE_COMPILE_DEFINITIONS "$<$<COMPILE_LANGUAGE:CXX>:__STDC_CONSTANT_MACROS>")
  set(FFmpeg_${component}_FOUND TRUE PARENT_SCOPE)
endfunction()

foreach(_ffmpeg_component avutil swresample swscale avcodec avformat avfilter avdevice postproc)
  _ffmpeg_add(${_ffmpeg_component})
  if(TARGET FFmpeg::${_ffmpeg_component})
    set(FFmpeg_${_ffmpeg_component}_FOUND TRUE)
    list(APPEND FFmpeg_LIBRARIES FFmpeg::${_ffmpeg_component})
  endif()
endforeach()

if(NOT TARGET FFmpeg::FFmpeg AND FFmpeg_LIBRARIES)
  add_library(FFmpeg::FFmpeg INTERFACE IMPORTED)
  set_target_properties(FFmpeg::FFmpeg PROPERTIES INTERFACE_LINK_LIBRARIES "${FFmpeg_LIBRARIES}")
endif()

set(FFmpeg_FOUND TRUE)
foreach(_ffmpeg_component IN LISTS FFmpeg_FIND_COMPONENTS)
  if(NOT FFmpeg_${_ffmpeg_component}_FOUND AND FFmpeg_FIND_REQUIRED_${_ffmpeg_component})
    set(FFmpeg_FOUND FALSE)
    set(FFmpeg_NOT_FOUND_MESSAGE "FFmpeg component ${_ffmpeg_component} is not in this package")
  endif()
endforeach()
