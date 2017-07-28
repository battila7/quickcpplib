# Adds standard ctest tests for each *.c;*.cpp;*.cxx in
# ${PROJECT_NAME}_TESTS for all ${PROJECT_NAME}_targets
#
# Sets ${PROJECT_NAME}_TEST_TARGETS to the test targets generated

if(NOT PROJECT_IS_DEPENDENCY)
  unset(CLANG_TIDY_EXECUTABLE)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/.clang-tidy" AND NOT DISABLE_CLANG_TIDY)
    find_program(CLANG_TIDY_EXECUTABLE "clang-tidy" DOC "Path to clang-tidy executable")
    if(CLANG_TIDY_EXECUTABLE MATCHES "CLANG_TIDY_EXECUTABLE-NOTFOUND")
      indented_message(WARNING "WARNING: .clang-tidy file found for project ${PROJECT_NAME}, yet clang-tidy not on PATH so disabling lint pass")
    endif()
  endif()
  
  if(DEFINED ${PROJECT_NAME}_TESTS)
    enable_testing()
    function(generate_tests)
      # Firstly get all non-source files
      foreach(testsource ${${PROJECT_NAME}_TESTS})
        if(NOT testsource MATCHES ".+/(.+)[.](c|cpp|cxx)$")
          list(APPEND testnonsources ${testsource})
        endif()
      endforeach()
      function(do_add_test outtarget testsource special nogroup)
        unset(${outtarget} PARENT_SCOPE)
        if(testsource MATCHES ".+/(.+)[.](c|cpp|cxx)$")
          # We'll assume the test name is the source file name
          set(testname ${CMAKE_MATCH_1})
          # Path could however be test/tests/<name>/*.cpp
          if(testsource MATCHES ".+/tests/([^/]+)/(.+)[.](c|cpp|cxx)$")
            set(testname ${CMAKE_MATCH_1})
          endif()
          set(thistestsources ${testsource})
          foreach(testnonsource ${testnonsources})
            if(testnonsource MATCHES ${testname})
              list(APPEND thistestsources ${testnonsource})
            endif()
          endforeach()
          foreach(_target ${${PROJECT_NAME}_TARGETS})
            set(target ${_target})
            if(nogroup)
              unset(group)
            elseif(target MATCHES "_hl$")
              set(group _hl)
            elseif(target MATCHES "_sl$")
              set(group _sl)
            elseif(target MATCHES "_dl$")
              set(group _dl)
            else()
              unset(group)
            endif()
            if(special STREQUAL "")
              set(target_name "${target}--${testname}")
            else()
              set(group _${special})
              set(target_name "${target}-${special}-${testname}")
              if(NOT target MATCHES "_hl$")
                set(target "${target}-${special}")
              endif()
            endif()
            add_executable(${target_name} ${thistestsources})
            set_target_properties(${target_name} PROPERTIES
              EXCLUDE_FROM_ALL ON
            )
            if(DEFINED CLANG_TIDY_EXECUTABLE AND NOT CLANG_TIDY_EXECUTABLE MATCHES "CLANG_TIDY_EXECUTABLE-NOTFOUND")
              if(MSVC)
                # Tell clang-tidy to interpret these parameters as clang-cl would
                set_target_properties(${target_name} PROPERTIES
                  CXX_CLANG_TIDY "${CLANG_TIDY_EXECUTABLE};-fms-extensions;-fms-compatibility-version=19;-D_M_AMD64=100;"
                )
              else()
                set_target_properties(${target_name} PROPERTIES
                  CXX_CLANG_TIDY "${CLANG_TIDY_EXECUTABLE}"
                )
              endif()
            endif()
            if(DEFINED group)
              add_dependencies(${group} ${target_name})
            endif()
            set(${outtarget} "${target_name}" PARENT_SCOPE)
            target_link_libraries(${target_name} ${target})
            set_target_properties(${target_name} PROPERTIES
              RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
              POSITION_INDEPENDENT_CODE ON
            )
            if(WIN32)
              target_compile_definitions(${target_name} PRIVATE _CRT_NONSTDC_NO_WARNINGS)                 # Shut up about using POSIX functions
            endif()
            if(MSVC)
              target_compile_options(${target_name} PRIVATE /W4)                                          # Stronger warnings
            else()
              target_compile_options(${target_name} PRIVATE -Wall -Wextra)                                # Stronger warnings
            endif()
          endforeach()
        endif()
      endfunction()
      
      # Deal with normal tests + special builds of them first
      set(testtargets)
      foreach(testsource ${${PROJECT_NAME}_TESTS})
        foreach(special ${SPECIAL_BUILDS} "")
          do_add_test(target_name "${testsource}" "${special}" OFF)
          if(DEFINED target_name)
            # This is a normal test target run for success
            list(APPEND testtargets "${target_name}")
            if(special STREQUAL "")
              # Output test detail to JUnit XML
              add_test(NAME ${target_name} CONFIGURATIONS Debug Release RelWithDebInfo MinSizeRel
                COMMAND $<TARGET_FILE:${target_name}> --reporter junit --out $<TARGET_FILE:${target_name}>.junit.xml
              )
            else()
              add_test(NAME ${target_name} COMMAND $<TARGET_FILE:${target_name}> CONFIGURATIONS ${special})
              if(DEFINED ${special}_LINK_FLAGS)
                _target_link_options(${target_name} ${${special}_LINK_FLAGS})
              endif()
              target_compile_options(${target_name} PRIVATE ${${special}_COMPILE_FLAGS})
              list(APPEND ${PROJECT_NAME}_${special}_TARGETS ${target_name})
            endif()
          endif()
        endforeach()
      endforeach()
      set(${PROJECT_NAME}_TEST_TARGETS ${testtargets} PARENT_SCOPE)
      foreach(special ${SPECIAL_BUILDS})
        set(${PROJECT_NAME}_${special}_TARGETS ${${PROJECT_NAME}_${special}_TARGETS} PARENT_SCOPE)
      endforeach()

      # Deal with tests which require the compilation to succeed
      foreach(testsource ${${PROJECT_NAME}_COMPILE_TESTS})
        do_add_test(target_name "${testsource}" "" OFF)
      endforeach()

      # Deal with tests which require the compilation to fail in an exact way
      foreach(testsource ${${PROJECT_NAME}_COMPILE_FAIL_TESTS})
        do_add_test(target_name "${testsource}" "" ON)
        if(DEFINED target_name)
          # Do not build these normally, only on request
          set_target_properties(${target_name} PROPERTIES
            EXCLUDE_FROM_ALL ON
            EXCLUDE_FROM_DEFAULT_BUILD ON
            CXX_CLANG_TIDY ""
          )
          # This test tries to build this test expecting failure
          add_test(NAME ${target_name}
            COMMAND ${CMAKE_COMMAND} --build . --target ${target_name} --config $<CONFIGURATION>
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
          )
          # Fetch the regex to detect correct failure
          file(STRINGS "${testsource}" firstline LIMIT_COUNT 2)
          list(GET firstline 1 firstline)
          set_tests_properties(${target_name} PROPERTIES PASS_REGULAR_EXPRESSION "${firstline}")
        endif()
      endforeach()
    endfunction()
    generate_tests()
  endif()

  # For all special builds, create custom "all" target for each of those so one can build "everything with asan" etc
  foreach(special ${SPECIAL_BUILDS})
    indented_message(STATUS "Creating non-default all target for special build ${PROJECT_NAME}-${special}")
    add_custom_target(${PROJECT_NAME}-${special} DEPENDS ${${PROJECT_NAME}_${special}_TARGETS})
    add_dependencies(_${special} ${PROJECT_NAME}-${special})
  endforeach()
  
  # We need to now decide on some default build target group. Prefer static libraries
  # unless this is a header only library
  if(TARGET ${PROJECT_NAME}_sl)
    set_target_properties(_sl PROPERTIES EXCLUDE_FROM_ALL OFF)
  else()
    set_target_properties(_hl PROPERTIES EXCLUDE_FROM_ALL OFF)
  endif()
endif()