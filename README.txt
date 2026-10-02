========================================================================
            PROYECTO FINAL - THEREMIN & LOOPER DSP (ZYNQ-7000)
                    Placa objetivo: Digilent Arty Z7-20
========================================================================

ESTRUCTURA DEL PROYECTO:
-----------------------
- Passthrough_v1/      : Proyecto completo de Vivado (Hardware / FPGA).
- Vitis_Loop_/         : Workspace de Vitis Unified IDE (Software Baremetal Dual-Core).
  * App/               : Codigo Nucleo 0 (UI LVGL, Encoders, Sintetizador).
  * Loop_y_SD/         : Codigo Nucleo 1 (Motor de Audio DMA, Looper, Grabacion FatFs SD).
  * platform/          : Plataforma BSP Zynq dual-core (Cortex-A9_0, Cortex-A9_1, FSBL).
  * theremin_dual_core/: System Project unificado.
  * Boot_image/        : Imagen BOOT.bin lista para grabar en memoria Flash QSPI.
- update_bitstream.ps1 : Script auxiliar de PowerShell para inyeccion rapida del .bit.

REQUISITOS PREVIOS:
-------------------
1. AMD Xilinx Vivado & Vitis Unified IDE (v2025.1 o v2024.2).
2. Board files de Digilent Arty Z7-20 instalados en Vivado.
3. Placa Digilent Arty Z7-20 conectada por micro-USB (modo JTAG).

INSTRUCCIONES DE USO:
--------------------

A. HARDWARE (Vivado):
   1. Abrir Vivado.
   2. Abrir el proyecto: Passthrough_v1/Passthrough_v1.xpr.
   3. Para compilar el hardware completo: Hacer clic en "Generate Bitstream".
   4. El bitstream resultante se genera en Passthrough_v1.runs/impl_1/design_1_wrapper.bit.

B. SOFTWARE (Vitis Unified IDE):
   1. Abrir Vitis Unified IDE.
   2. Seleccionar como Workspace la carpeta: Vitis_Loop_/
   3. En el panel lateral izquierdo "FLOW", podras ver los componentes:
      - platform
      - App
      - Loop_y_SD
      - theremin_dual_core
   4. Compilacion:
      - Hacer clic en "Build" dentro del componente que desees compilar.
   5. Ejecucion en Hardware (JTAG):
      - En "theremin_dual_core", hacer clic en "Run" o "Debug" (configuracion dual-core).

C. ACTUALIZACION RAPIDA DE BITSTREAM:
   Si modificas la logica en Vivado y generas un nuevo bitstream, puedes ejecutar
   el script 'update_bitstream.ps1' con PowerShell para inyectar el nuevo .bit 
   directamente en Vitis sin tener que regenerar toda la plataforma.
========================================================================
