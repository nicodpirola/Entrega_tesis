#ifndef IPC_H
#define IPC_H

#include "xil_types.h"

#define IPC_BASE_ADDR 0xFFFF0000

typedef enum {
    HW_MODE_IDLE = 0,
    HW_MODE_REC  = 1,
    HW_MODE_PLAY = 2,
    HW_MODE_OD   = 3
} hw_mode_t;

typedef struct {
    volatile hw_mode_t hw_mode;
    volatile int sd_recording;
    
    volatile u32 loop_index;
    volatile u32 loop_length;
    volatile int core1_ready;

    volatile int preset_cmd;
    volatile int preset_status;
    volatile int preset_data[6][4];
} IPC_Data;

#define IPC ((IPC_Data*)IPC_BASE_ADDR)

#endif
