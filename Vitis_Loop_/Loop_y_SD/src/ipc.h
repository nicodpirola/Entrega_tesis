#ifndef IPC_H
#define IPC_H

#include "xil_types.h"

// Dirección memoria compartida 
#define IPC_BASE_ADDR 0xFFFF0000

#define LOOP_SAMPLE_RATE  48000u
#define LOOP_MAX_SECONDS  120u
#define LOOP_MAX_SAMPLES  (LOOP_SAMPLE_RATE * LOOP_MAX_SECONDS)

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

    // Diagnostico del looper. Se agregan al final para no mover los campos existentes.
    volatile u32 diag_sequence;          // aumenta al cerrar REC u OVERDUB
    volatile u32 diag_event;             // 1=fin REC, 2=fin OVERDUB
    volatile u32 diag_record_us;         // duracion de REC medida por Core 1
    volatile u32 diag_recorded_words;    // palabras AXI guardadas en el loop
    volatile u32 diag_stream_word_rate;  // palabras AXI por segundo
    volatile u32 diag_seam_left;         // salto abs. ultima/primera muestra izquierda
    volatile u32 diag_seam_right;        // salto abs. ultima/primera muestra derecha
    volatile u32 diag_record_saturated;  // muestras saturadas durante REC
    volatile u32 diag_overdub_words;     // palabras reescritas durante OVERDUB
    volatile u32 diag_overdub_changed;   // palabras cuyo audio cambio
    volatile u32 diag_overdub_max_delta; // mayor cambio de amplitud del OVERDUB
    volatile u32 diag_overdub_saturated; // muestras saturadas durante OVERDUB
    volatile u32 diag_dma_rx_errors;
    volatile u32 diag_dma_tx_errors;
    volatile u32 diag_transfer_errors;
    volatile u32 diag_record_same_prev2;
    volatile u32 diag_record_compared;
    volatile u32 diag_overdub_mean_delta;
    volatile u32 diag_overdub_large_delta;
    volatile u32 diag_overdub_start_index;
    volatile u32 diag_overdub_end_index;
    volatile u32 diag_overdub_max_index;
    volatile u32 diag_start_rx_errors;
    volatile u32 diag_start_tx_errors;
    volatile u32 diag_resyncs;           // resincronizaciones del stream TX (Core 1)
} IPC_Data;

#define IPC ((IPC_Data*)IPC_BASE_ADDR)
#endif
