#ifndef IPC_H
#define IPC_H

#include "xil_types.h"

// Dirección memoria compartida 
#define IPC_BASE_ADDR 0xFFFF0000

// Estructura de comunicación entre cores
typedef struct {
    // Comandos desde el núcleo 0 (UI) hacia el núcleo 1 (Audio)
    volatile int hw_mode;       // 0=IDLE, 1=REC, 2=PLAY, 3=OVERDUB
    volatile int sd_recording;  // 1=Grabar a SD, 0=Detener
    
    // Status desde el núcleo 1 a 0
    volatile u32 loop_index;
    volatile u32 loop_length;
    volatile int core1_ready;   // 1 cuando el Núcleo 1 terminó de arrancar

    // Presets (SD Card)
    volatile int preset_cmd;    // 0=IDLE, 1..3=SAVE Slot 1..3, 4..6=LOAD Slot 1..3
    volatile int preset_status; // 0=IDLE, 1=BUSY, 2=OK, 3=ERROR
    volatile int preset_data[6][4];
} IPC_Data;

#define IPC ((IPC_Data*)IPC_BASE_ADDR)
#endif
