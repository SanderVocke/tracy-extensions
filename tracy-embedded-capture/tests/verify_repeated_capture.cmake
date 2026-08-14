if(NOT DEFINED FIXTURE OR NOT DEFINED TRACY_QUERY OR
   NOT DEFINED FIRST_OUTPUT OR NOT DEFINED SECOND_OUTPUT)
    message(FATAL_ERROR "FIXTURE, TRACY_QUERY, FIRST_OUTPUT, and SECOND_OUTPUT are required")
endif()

foreach(_output IN ITEMS "${FIRST_OUTPUT}" "${SECOND_OUTPUT}")
    file(REMOVE "${_output}")
    file(GLOB _partials "${_output}.*.partial")
    if(_partials)
        file(REMOVE ${_partials})
    endif()
endforeach()

execute_process(
    COMMAND "${FIXTURE}" "${FIRST_OUTPUT}" "${SECOND_OUTPUT}"
    RESULT_VARIABLE _fixture_result
    OUTPUT_VARIABLE _fixture_stdout
    ERROR_VARIABLE _fixture_stderr
    TIMEOUT 60)
if(NOT _fixture_result EQUAL 0)
    message(FATAL_ERROR "repeated embedded fixture failed (${_fixture_result})\n${_fixture_stdout}\n${_fixture_stderr}")
endif()

set(_expected "first-capture" "second-capture")
set(_index 0)
foreach(_output IN ITEMS "${FIRST_OUTPUT}" "${SECOND_OUTPUT}")
    list(GET _expected ${_index} _marker)
    execute_process(
        COMMAND "${TRACY_QUERY}" check "${_output}"
        RESULT_VARIABLE _check_result
        OUTPUT_VARIABLE _check_stdout
        ERROR_VARIABLE _check_stderr)
    if(NOT _check_result EQUAL 0)
        message(FATAL_ERROR "repeated capture check failed for ${_output}\n${_check_stdout}\n${_check_stderr}")
    endif()
    execute_process(
        COMMAND "${TRACY_QUERY}" query --kind message --detail full "${_output}"
        RESULT_VARIABLE _query_result
        OUTPUT_VARIABLE _query_stdout
        ERROR_VARIABLE _query_stderr)
    if(NOT _query_result EQUAL 0 OR NOT _query_stdout MATCHES "${_marker}")
        message(FATAL_ERROR "capture ${_output} is missing ${_marker}\n${_query_stdout}\n${_query_stderr}")
    endif()
    file(GLOB _partials "${_output}.*.partial")
    if(_partials)
        message(FATAL_ERROR "repeated capture left partial files: ${_partials}")
    endif()
    math(EXPR _index "${_index} + 1")
endforeach()
