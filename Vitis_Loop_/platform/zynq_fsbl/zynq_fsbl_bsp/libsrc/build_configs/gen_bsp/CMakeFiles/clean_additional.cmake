# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\diskio.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\ff.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\ffconf.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\sleep.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xilffs.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xilffs_config.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xilrsa.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xiltimer.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\include\\xtimer_config.h"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\lib\\libxilffs.a"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\lib\\libxilrsa.a"
  "X:\\Entrega_Tesis\\Vitis_Loop_\\platform\\zynq_fsbl\\zynq_fsbl_bsp\\lib\\libxiltimer.a"
  )
endif()
