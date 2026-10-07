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




