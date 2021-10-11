# Souffle - A Datalog Compiler
# Copyright (c) 2021 The Souffle Developers. All rights reserved
# Licensed under the Universal Permissive License v 1.0 as shown at:
# - https://opensource.org/licenses/UPL
# - <souffle root>/licenses/SOUFFLE-UPL.txt

function(SOUFFLE_SETUP_INTEGRATION_TEST_DIR)
    cmake_parse_arguments(
        PARAM
        ""
        "TEST_NAME;QUALIFIED_TEST_NAME;DATA_CHECK_DIR;OUTPUT_DIR;EXTRA_DATA;FIXTURE_NAME"
        "TEST_LABELS"
        ${ARGV}
    )

if ("provenance" IN_LIST TEST_LABELS)
        set (PARAM_EXTRA_DATA "provenance")
    endif()

    # Set up the test directory
    add_test(NAME ${PARAM_QUALIFIED_TEST_NAME}_setup
             COMMAND "${PROJECT_SOURCE_DIR}/cmake/setup_test_dir.sh" "${PARAM_DATA_CHECK_DIR}" "${PARAM_OUTPUT_DIR}"
                                                    "${PARAM_TEST_NAME}" "${PARAM_EXTRA_DATA}")
    set_tests_properties(${PARAM_QUALIFIED_TEST_NAME}_setup PROPERTIES
                         LABELS "${PARAM_TEST_LABELS}"
                         FIXTURES_SETUP ${PARAM_FIXTURE_NAME}_setup)

endfunction()

function(SOUFFLE_RUN_INTEGRATION_TEST)
    cmake_parse_arguments(
        PARAM
        ""
        "TEST_NAME;QUALIFIED_TEST_NAME;INPUT_DIR;OUTPUT_DIR;FIXTURE_NAME;SOUFFLE_PARAMS;NEGATIVE"
        "TEST_LABELS"
        ${ARGV}
    )

    # Run souffle (through the shell, so we can easily redirect)
    set(SOUFFLE_CMD "set -e$<SEMICOLON> '$<TARGET_FILE:souffle>' ${PARAM_SOUFFLE_PARAMS} '${PARAM_INPUT_DIR}/${PARAM_TEST_NAME}.dl'\\
                    1> '${PARAM_TEST_NAME}.out'\\
                    2> '${PARAM_TEST_NAME}.err'")

    if ("provenance" IN_LIST TEST_LABELS)
        set (SOUFFLE_CMD "${SOUFFLE_CMD} < '${PARAM_TEST_NAME}.in'")
    endif()

    add_test(NAME ${PARAM_QUALIFIED_TEST_NAME}_run_souffle
        COMMAND sh -c "${SOUFFLE_CMD}")

    set_tests_properties(${PARAM_QUALIFIED_TEST_NAME}_run_souffle PROPERTIES
                         # Switch to output dir so that any "extra" files generated by
                         # souffle are dropped in there
                         WORKING_DIRECTORY "${PARAM_OUTPUT_DIR}"
                         LABELS "${PARAM_TEST_LABELS}"
                         FIXTURES_SETUP ${PARAM_FIXTURE_NAME}_run_souffle
                         FIXTURES_REQUIRED ${PARAM_FIXTURE_NAME}_setup)

    if (PARAM_NEGATIVE)
        # Mark the souffle run as "will fail" for negative tests
        set_tests_properties(${PARAM_QUALIFIED_TEST_NAME}_run_souffle PROPERTIES WILL_FAIL TRUE)
    endif()

endfunction()

function(SOUFFLE_COMPARE_STD_OUTPUTS)
    cmake_parse_arguments(
        PARAM
        ""
        "TEST_NAME;QUALIFIED_TEST_NAME;OUTPUT_DIR;EXTRA_DATA;RUN_AFTER_FIXTURE"
        "TEST_LABELS"
        ${ARGV}
    )

    add_test(NAME ${PARAM_QUALIFIED_TEST_NAME}_compare_std_outputs
             COMMAND "${PROJECT_SOURCE_DIR}/cmake/check_std_outputs.sh" "${PARAM_TEST_NAME}" "${PARAM_EXTRA_DATA}")
    set_tests_properties(${PARAM_QUALIFIED_TEST_NAME}_compare_std_outputs PROPERTIES
                         WORKING_DIRECTORY "${PARAM_OUTPUT_DIR}"
                         LABELS "${PARAM_TEST_LABELS}"
                         FIXTURES_REQUIRED ${PARAM_RUN_AFTER_FIXTURE})
endfunction()

function(SOUFFLE_COMPARE_CSV)
    cmake_parse_arguments(
        PARAM
        ""
        "QUALIFIED_TEST_NAME;INPUT_DIR;OUTPUT_DIR;EXTRA_DATA;RUN_AFTER_FIXTURE;NEGATIVE"
        "TEST_LABELS"
        ${ARGV}
    )

    if (NOT PARAM_NEGATIVE)
        # If there are "extra outputs", handle them
        if (PARAM_EXTRA_DATA)
            if (PARAM_EXTRA_DATA STREQUAL "gzip")
                set(EXTRA_BINARY "${GZIP_BINARY}")
            elseif (PARAM_EXTRA_DATA STREQUAL "sqlite3")
                set(EXTRA_BINARY "${SQLITE3_BINARY}")
            elseif (PARAM_EXTRA_DATA STREQUAL "json")
                set(EXTRA_BINARY "")
            else()
                message(FATAL_ERROR "Unknown extra data type ${PARAM_EXTRA_DATA}")
            endif()
        endif()

        add_test(NAME ${QUALIFIED_TEST_NAME}_compare_csv
             COMMAND "${PROJECT_SOURCE_DIR}/cmake/check_test_results.sh"
                                            "${PARAM_INPUT_DIR}" ${PARAM_EXTRA_DATA} "${EXTRA_BINARY}")

        set_tests_properties(${QUALIFIED_TEST_NAME}_compare_csv PROPERTIES
                        WORKING_DIRECTORY "${PARAM_OUTPUT_DIR}"
                        LABELS "${PARAM_TEST_LABELS}"
                        FIXTURES_REQUIRED ${PARAM_RUN_AFTER_FIXTURE})
    endif()
endfunction()

function(SOUFFLE_RUN_TEST_HELPER)
    # PARAM_CATEGORY - e.g. syntactic, example etc.
    # PARAM_TEST_NAME - the name of the test, the short directory name under tests/<category>/<test_name>
    # PARAM_COMPILED - with or without -c
    # PARAM_FUNCTORS - with -L for finding functor library in the testsuite
    # PARAM_NEGATIVE - should it fail or not
    # PARAM_MULTI_TEST - used to distinguish "multi-tests", sort of left over from automake
    #                           Basically, the same test dir has multiple sets of facts/outputs
    #                           We should just get rid of this and make multiple tests
    #                           It also means we need to use slightly different naming for tests
    #                           and input paths
    # PARAM_FACTS_DIR_NAME - the name of the "facts" subdirectory in each test.
    #                        Usually just "facts" but can be different when running multi-tests
    cmake_parse_arguments(
        PARAM
        "COMPILED;FUNCTORS;NEGATIVE;MULTI_TEST" # Options
        "TEST_NAME;CATEGORY;FACTS_DIR_NAME;EXTRA_DATA" #Single valued options
        ""
        ${ARGV}
    )

    if (PARAM_COMPILED)
        set(EXTRA_FLAGS "-c")
        set(EXEC_STYLE "compiled")
        set(SHORT_EXEC_STYLE "_c")
    else()
        set(EXEC_STYLE "interpreted")
        set(SHORT_EXEC_STYLE "")
    endif()

    if (PARAM_FUNCTORS)
        set(EXTRA_FLAGS "${EXTRA_FLAGS} '-L${CMAKE_CURRENT_BINARY_DIR}/${PARAM_TEST_NAME}'")
    endif()

    if (NOT PARAM_FACTS_DIR_NAME)
        set(PARAM_FACTS_DIR_NAME "facts")
    endif()

    set(INPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/${PARAM_TEST_NAME}")
    set(FACTS_DIR "${INPUT_DIR}/${PARAM_FACTS_DIR_NAME}")

    if (PARAM_MULTI_TEST)
        set(DATA_CHECK_DIR "${INPUT_DIR}/${PARAM_FACTS_DIR_NAME}")
        set(MT_EXTRA_SUFFIX "_${PARAM_FACTS_DIR_NAME}")
    else()
        set(DATA_CHECK_DIR "${INPUT_DIR}")
        set(MT_EXTRA_SUFFIX "")
    endif()

    set(OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/${PARAM_TEST_NAME}${MT_EXTRA_SUFFIX}_${EXEC_STYLE}")
    # Give the test a name which has good info about it when running
    # People can then search for the test by the name, or the labels we create
    set(QUALIFIED_TEST_NAME ${PARAM_CATEGORY}/${PARAM_TEST_NAME}${MT_EXTRA_SUFFIX}${SHORT_EXEC_STYLE})
    set(FIXTURE_NAME ${QUALIFIED_TEST_NAME}_fixture)

    if(PARAM_NEGATIVE)
        set(POS_LABEL "negative")
    else()
        set(POS_LABEL "positive")
    endif()

    # Label the tests as e.g. "semantic", compiled/interpreted, positive/negative, and integration
    set(TEST_LABELS "${PARAM_CATEGORY};${EXEC_STYLE};${POS_LABEL};integration")

    souffle_setup_integration_test_dir(TEST_NAME ${PARAM_TEST_NAME}
                                       QUALIFIED_TEST_NAME ${QUALIFIED_TEST_NAME}
                                       DATA_CHECK_DIR ${DATA_CHECK_DIR}
                                       OUTPUT_DIR ${OUTPUT_DIR}
                                       EXTRA_DATA ${PARAM_EXTRA_DATA}
                                       FIXTURE_NAME ${FIXTURE_NAME}
                                       TEST_LABELS ${TEST_LABELS})

    if (OPENMP_FOUND)
        set(SOUFFLE_PARAMS "${EXTRA_FLAGS} -j8 -D . -F '${FACTS_DIR}'")
    else()
        set(SOUFFLE_PARAMS "${EXTRA_FLAGS} -D . -F '${FACTS_DIR}'")
    endif()

    souffle_run_integration_test(TEST_NAME ${PARAM_TEST_NAME}
                                 QUALIFIED_TEST_NAME ${QUALIFIED_TEST_NAME}
                                 INPUT_DIR ${INPUT_DIR}
                                 OUTPUT_DIR ${OUTPUT_DIR}
                                 FIXTURE_NAME ${FIXTURE_NAME}
                                 NEGATIVE ${PARAM_NEGATIVE}
                                 SOUFFLE_PARAMS ${SOUFFLE_PARAMS}
                                 TEST_LABELS ${TEST_LABELS})

    souffle_compare_std_outputs(TEST_NAME ${PARAM_TEST_NAME}
                                 QUALIFIED_TEST_NAME ${QUALIFIED_TEST_NAME}
                                 OUTPUT_DIR ${OUTPUT_DIR}
                                 EXTRA_DATA ${PARAM_EXTRA_DATA}
                                 RUN_AFTER_FIXTURE ${FIXTURE_NAME}_run_souffle
                                 TEST_LABELS ${TEST_LABELS})

    souffle_compare_csv(QUALIFIED_TEST_NAME ${QUALIFIED_TEST_NAME}
                        INPUT_DIR ${INPUT_DIR}
                        OUTPUT_DIR ${OUTPUT_DIR}
                        EXTRA_DATA ${PARAM_EXTRA_DATA}
                        RUN_AFTER_FIXTURE ${FIXTURE_NAME}_run_souffle
                        NEGATIVE ${PARAM_NEGATIVE}
                        TEST_LABELS ${TEST_LABELS})
endfunction()


# --------------------------------------------------
# Here are the "user-facing" testing functions
# --------------------------------------------------

# Create a souffle unit-test.  Specifically, this is for the
# few binaries in the src tree.  It does a little bit of renaming/
# name normalization and links in libsouffle
function(SOUFFLE_ADD_BINARY_TEST TEST_NAME CATEGORY)
    # PARAM_SOUFFLE_HEADERS_ONLY - don't depend on compiling `libsouffle`; saves time and allows independent tests
    cmake_parse_arguments(
        PARSE_ARGV 2
        PARAM
        "SOUFFLE_HEADERS_ONLY" # Options
        "" #Single valued options
        "" #Multi-value options
    )

    # The naming of the test targets is inconsistent in souffle
    # Keep the file name the same (for now) but rename the rest
    string(REGEX REPLACE "^test_" "" SHORT_TEST_NAME ${TEST_NAME})
    string(REGEX REPLACE "_test$" "" SHORT_TEST_NAME ${SHORT_TEST_NAME})
    set(TARGET_NAME "test_${SHORT_TEST_NAME}")

    add_executable(${TARGET_NAME} ${TEST_NAME}.cpp)
    set(CMAKE_CXX_STANDARD 17)

    if (PARAM_SOUFFLE_HEADERS_ONLY)
        get_target_property(SOUFFLE_COMPILE_EXTS libsouffle CXX_EXTENSIONS)
        get_target_property(SOUFFLE_COMPILE_DEFS libsouffle INTERFACE_COMPILE_DEFINITIONS)
        get_target_property(SOUFFLE_COMPILE_FEAT libsouffle INTERFACE_COMPILE_FEATURES)
        get_target_property(SOUFFLE_COMPILE_OPTS libsouffle COMPILE_OPTIONS)
        get_target_property(SOUFFLE_INCLUDE_DIRS libsouffle INTERFACE_INCLUDE_DIRECTORIES)

        set_target_properties(${TARGET_NAME} PROPERTIES CXX_EXTENSIONS SOUFFLE_COMPILE_EXTS)
        target_compile_definitions(${TARGET_NAME} PRIVATE ${SOUFFLE_COMPILE_DEFS})
        target_compile_features(${TARGET_NAME} PRIVATE ${SOUFFLE_COMPILE_FEAT})
        target_compile_options(${TARGET_NAME} PRIVATE ${SOUFFLE_COMPILE_OPTS})
        target_include_directories(${TARGET_NAME} PRIVATE ${SOUFFLE_INCLUDE_DIRS})
    else()
        target_link_libraries(${TARGET_NAME} libsouffle)
    endif()

    set(QUALIFIED_TEST_NAME ${SHORT_TEST_NAME})
    add_test(NAME ${QUALIFIED_TEST_NAME} COMMAND ${TARGET_NAME})
    set_tests_properties(${QUALIFIED_TEST_NAME} PROPERTIES LABELS "unit_test;${CATEGORY}")
endfunction()

# Run a souffle test, both as interpred and as compiled
# For additional parameters, see souffle_run_test_helper above
function(SOUFFLE_RUN_TEST)
    souffle_run_test_helper(${ARGV})
    souffle_run_test_helper(${ARGV} COMPILED)
endfunction()

# A helper to make it easier to specify the category positionally
function(SOUFFLE_POSITIVE_TEST TEST_NAME CATEGORY)
    souffle_run_test(TEST_NAME ${TEST_NAME}
                     CATEGORY ${CATEGORY})
endfunction()

# A helper to make it easier to specify the category positionally
function(SOUFFLE_NEGATIVE_TEST TEST_NAME CATEGORY)
    souffle_run_test(NEGATIVE
                     TEST_NAME ${TEST_NAME}
                     CATEGORY ${CATEGORY})
endfunction()

# A helper to allow the creation of multi-tests.  In addition to the
# parameters of souffle_run_test, allso allows the specification of
# FACTS_DIR_NAMES - these are the names of the subdirectories of the
# test
function(SOUFFLE_POSITIVE_MULTI_TEST)
    cmake_parse_arguments(
        PARAM
        ""
        "TEST_NAME;CATEGORY" #Single valued options
        "FACTS_DIR_NAMES"
        ${ARGV}
    )

    foreach(FACTS_DIR_NAME ${PARAM_FACTS_DIR_NAMES})
        souffle_run_test(TEST_NAME ${PARAM_TEST_NAME}
                         MULTI_TEST
                         CATEGORY ${PARAM_CATEGORY}
                         FACTS_DIR_NAME ${FACTS_DIR_NAME})
    endforeach()
endfunction()
