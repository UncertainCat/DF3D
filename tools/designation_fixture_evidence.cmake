# ctest driver: generate the synthetic before/after designation recordings,
# then replay them through fixture_evidence (tile 127,61,165; unit 988).
file(MAKE_DIRECTORY "${WORK_DIR}")
execute_process(COMMAND "${GENERATOR}" "${WORK_DIR}/before.df3dfix" "${WORK_DIR}/after.df3dfix"
                RESULT_VARIABLE generated)
if(NOT generated EQUAL 0)
  message(FATAL_ERROR "make_designation_fixture failed (${generated})")
endif()
execute_process(COMMAND "${EVIDENCE}" "${WORK_DIR}/before.df3dfix" "${WORK_DIR}/after.df3dfix" 127 61 165 988
                RESULT_VARIABLE replayed)
if(NOT replayed EQUAL 0)
  message(FATAL_ERROR "fixture_evidence failed (${replayed})")
endif()
