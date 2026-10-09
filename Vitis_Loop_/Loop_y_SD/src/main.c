// =============================================================================
// Nucleo 1: motor de audio (DMA), looper y grabacion a SD
//
// ESQUEMA DEL LOOPER (reescrito 2026-09-30)
// -----------------------------------------------------------------------------
// El mezclador del PL (axi_stream_looper_mixer) queda SIEMPRE en modo 2
// (vivo + RAM). El DMA TX corre siempre, en paso con el RX: por cada paquete
// RX que termina se encola exactamente un paquete TX. Ese paquete trae el loop
// (PLAY/OVERDUB) o ceros (IDLE/REC). Vivo + 0 = vivo, asi que en IDLE/REC se
// escucha lo mismo que antes.
//
// Ventajas respecto del esquema anterior:
//   - El FIFO de TX nunca se vacia: el "sample & hold" del mezclador no actua
//     (era el pop al arrancar el loop).
//   - Nunca quedan restos de un loop viejo en el FIFO ni el DMA queda trabado.
//   - La relacion entre la palabra TX que suena y la palabra RX que vuelve es
//     FIJA, entonces el overdub se escribe en la posicion correcta (antes se
//     corria y se sentia que el loop "saltaba/aceleraba" donde se activaba).
//   - Micro-fades en el empalme del loop, al entrar/salir del overdub y al
//     parar, para evitar clicks.
//
// Convencion de indices:
//   j = numero del paquete RX que acaba de terminar (IOC).
//   El paquete TX encolado en el IOC j se mezcla durante el paquete RX
//   j + TX_AHEAD. La palabra TX arranca X_EST palabras despues del inicio del
//   paquete RX (latencia del handler al sincronizar).
// =============================================================================

#include <stdio.h>
#include <stdint.h>
#include "xparameters.h"
#include "xscutimer.h"
#include "xiltimer.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "ff.h"
#include "sleep.h"
#include "xil_mmu.h"
#include "ipc.h"

#define DMA_DEV_ID          XPAR_XAXIDMA_0_BASEADDR
#define PACKET_SIZE         512     // palabras por paquete DMA (= PKT_SIZE del PL)
#define MAX_SAMPLES         LOOP_MAX_SAMPLES
#define MAX_SD_SAMPLES      (48000 * 300)

#define TX_AHEAD            2       // paquetes de anticipacion del TX (margen ~1 paquete)
#define X_EST               2       // palabras de desfase TX/RX estimado al sincronizar
#define FADE_WORDS          256     // largo de los micro-fades (128 frames estereo)
#define MIN_OD_LEN          (4 * PACKET_SIZE)
#define POS_NONE            0xFFFFFFFFu
#define POS_RING            8       // potencia de 2
#define TX_BUFS             4

#define I2S_RX_BASE         0x43C00000
#define I2S_TX_BASE         0x43C10000
#define GPIO_MIXER_BASE     0x41200000
#define MIXER_MODE_MIX      2u      // vivo + RAM, consume TX siempre

XAxiDma AxiDma;
XScuTimer ScuTimer;

// Buffers DMA
u32 rx_ping[PACKET_SIZE] __attribute__((aligned(32)));
u32 rx_pong[PACKET_SIZE] __attribute__((aligned(32)));
static u32 tx_buf[TX_BUFS][PACKET_SIZE] __attribute__((aligned(32)));

u32 LoopBuffer[MAX_SAMPLES + PACKET_SIZE] __attribute__((aligned(32)));
u32 SdRecordBuffer[MAX_SD_SAMPLES] __attribute__((aligned(32)));

volatile u32 sd_length = 0;

// -----------------------------------------------------------------------------
// Estado del looper (propiedad exclusiva del Core 1)
// -----------------------------------------------------------------------------
typedef enum { LS_IDLE = 0, LS_REC = 1, LS_PLAY = 2, LS_OD = 3 } loop_state_t;

static loop_state_t lstate = LS_IDLE;
static u32 loop_len = 0;          // largo del loop en palabras (multiplo de PACKET_SIZE)
static u32 rec_len = 0;           // palabras grabadas en REC
static u32 play_pos = 0;          // proxima posicion del loop a encolar en TX
static u32 tx_pos[POS_RING];      // posicion del loop mezclada en el paquete RX j (POS_NONE = ceros)
static u32 rx_pkt = 0;            // numero del paquete RX que termino
static int fade_out_pending = 0;  // proximo paquete TX: ultimo pedazo del loop con fade-out
static int od_first = 0;          // primer paquete de overdub: fade-in
static int tx_buf_idx = 0;

// Sincronizacion del stream TX
static int     tx_running = 0;    // 0 = drenando / esperando para (re)sincronizar
static XTime   sync_after = 0;    // no sincronizar antes de este instante
static XTime   last_ioc = 0;
static u64     avg_gap = 0;       // promedio del intervalo entre IOCs (ticks)

// Grabacion a SD: antes de guardar se encolan ceros para que el FIFO quede en silencio
static volatile int sd_save_request = 0;
static volatile int sd_quiesced = 0;
static int quiesce_left = 0;

// Diagnostico
static XTime record_start_ticks;
static u32 od_words = 0;
static u32 od_start_pos = 0;

// -----------------------------------------------------------------------------
// Utilidades de muestras (formato I2S AXIS: audio 24 bits en [27:4])
// -----------------------------------------------------------------------------
static inline int32_t word_audio(u32 w) {
    return ((int32_t)(w << 4)) >> 8;
}

static inline u32 audio_word(int32_t a) {
    return ((u32)a & 0x00FFFFFFu) << 4;
}

static inline u32 abs_delta24(int32_t a, int32_t b) {
    s64 d = (s64)a - (s64)b;
    return (u32)(d < 0 ? -d : d);
}

// Mezcla lineal: a + (b - a) * w / den
static inline int32_t lerp_audio(int32_t a, int32_t b, u32 w, u32 den) {
    return a + (int32_t)(((s64)(b - a) * (s64)w) / (s64)den);
}

static inline void publish_diagnostic(u32 event) {
    IPC->diag_event = event;
    __asm__ volatile("dmb sy" ::: "memory");
    IPC->diag_sequence++;
}

static inline int start_dma(XAxiDma *dma, UINTPTR address, u32 bytes, int direction) {
    int status = XAxiDma_SimpleTransfer(dma, address, bytes, direction);
    if (status != XST_SUCCESS) {
        IPC->diag_transfer_errors++;
        if (direction == XAXIDMA_DEVICE_TO_DMA) IPC->diag_start_rx_errors++;
        else IPC->diag_start_tx_errors++;
    }
    return status;
}

static int wait_tx_idle(XAxiDma *dma) {
    XTime t0, t;
    XTime_GetTime(&t0);
    while (XAxiDma_Busy(dma, XAXIDMA_DMA_TO_DEVICE)) {
        XTime_GetTime(&t);
        if ((t - t0) > (COUNTS_PER_SECOND / 500)) return 0;   // 2 ms
    }
    return 1;
}

// -----------------------------------------------------------------------------
// Armado de paquetes TX
// -----------------------------------------------------------------------------
static void fill_from_loop(u32 *dst, u32 pos, int fade_out) {
    for (u32 i = 0; i < PACKET_SIZE; i++) {
        u32 p = pos + i;
        if (p >= loop_len) p -= loop_len;
        u32 w = LoopBuffer[p];
        if (fade_out && i >= PACKET_SIZE - FADE_WORDS) {
            u32 k = PACKET_SIZE - 1 - i;     // FADE_WORDS-1 .. 0
            w = audio_word(lerp_audio(0, word_audio(w), k, FADE_WORDS));
        }
        dst[i] = w;
    }
}
// Encola el paquete TX que se va a mezclar durante el paquete RX 'jq'
static int queue_tx_packet(u32 jq) {
    u32 *buf = tx_buf[tx_buf_idx];
    tx_buf_idx = (tx_buf_idx + 1) % TX_BUFS;
    u32 slot = jq & (POS_RING - 1);

    int playing = (lstate == LS_PLAY || lstate == LS_OD) && loop_len > 0 && quiesce_left == 0;

    if (playing) {
        fill_from_loop(buf, play_pos, 0);
        tx_pos[slot] = play_pos;
        play_pos += PACKET_SIZE;
        if (play_pos >= loop_len) play_pos -= loop_len;
    } else if (fade_out_pending && loop_len > 0) {
        fill_from_loop(buf, play_pos, 1);
        tx_pos[slot] = POS_NONE;
        fade_out_pending = 0;
        loop_len = 0;
        IPC->loop_length = 0;
    } else {
        for (u32 i = 0; i < PACKET_SIZE; i++) buf[i] = 0;
        tx_pos[slot] = POS_NONE;
    }

    Xil_DCacheFlushRange((UINTPTR)buf, PACKET_SIZE * sizeof(u32));
    if (!wait_tx_idle(&AxiDma)) IPC->diag_dma_tx_errors++;
    return start_dma(&AxiDma, (UINTPTR)buf, PACKET_SIZE * sizeof(u32), XAXIDMA_DMA_TO_DEVICE);
}

static void request_resync(XTime now, u64 delay) {
    tx_running = 0;
    sync_after = now + delay;
    for (int i = 0; i < POS_RING; i++) tx_pos[i] = POS_NONE;
    IPC->diag_resyncs++;
}

// -----------------------------------------------------------------------------
// Looper: escritura de overdub y cierre de grabacion
// -----------------------------------------------------------------------------
// ramp: 0 = sin rampa, 1 = fade-in (entrada), -1 = fade-out (salida)
static void overdub_write(const u32 *rx, u32 j, int ramp) {
    u32 pos_now  = tx_pos[j & (POS_RING - 1)];
    u32 pos_prev = tx_pos[(j - 1) & (POS_RING - 1)];

    for (u32 i = 0; i < PACKET_SIZE; i++) {
        u32 base, off;
        if (i >= X_EST) { base = pos_now;  off = i - X_EST; }
        else            { base = pos_prev; off = PACKET_SIZE + i - X_EST; }
        if (base == POS_NONE) continue;

        u32 dst = base + off;
        while (dst >= loop_len) dst -= loop_len;

        u32 w = rx[i];
        if (ramp != 0) {
            u32 k = (ramp > 0) ? i : (PACKET_SIZE - 1 - i);
            w = audio_word(lerp_audio(word_audio(LoopBuffer[dst]), word_audio(w), k, PACKET_SIZE));
        }
        LoopBuffer[dst] = w;
        od_words++;
    }
}

static void finish_recording(void) {
    XTime t_end;
    XTime_GetTime(&t_end);
    u64 us = ((u64)(t_end - record_start_ticks) * 1000000ULL) / COUNTS_PER_SECOND;

    IPC->diag_record_us = (u32)us;
    IPC->diag_recorded_words = rec_len;
    IPC->diag_stream_word_rate = us > 0 ? (u32)(((u64)rec_len * 1000000ULL) / us) : 0;
    if (rec_len >= 4) {
        IPC->diag_seam_left  = abs_delta24(word_audio(LoopBuffer[0]), word_audio(LoopBuffer[rec_len - 2]));
        IPC->diag_seam_right = abs_delta24(word_audio(LoopBuffer[1]), word_audio(LoopBuffer[rec_len - 1]));
    }

    if (rec_len < MIN_OD_LEN) {          // demasiado corto: se descarta
        lstate = LS_IDLE;
        loop_len = 0;
        IPC->hw_mode = 0;
        IPC->loop_length = 0;
        publish_diagnostic(1);
        return;
    }

    loop_len = rec_len;

    // Micro-fades en el empalme: evita el click entre la ultima y la primera muestra
    for (u32 i = 0; i < FADE_WORDS; i++) {
        LoopBuffer[i] = audio_word(lerp_audio(0, word_audio(LoopBuffer[i]), i, FADE_WORDS));
        u32 e = loop_len - 1 - i;
        LoopBuffer[e] = audio_word(lerp_audio(0, word_audio(LoopBuffer[e]), i, FADE_WORDS));
    }

    play_pos = 0;
    lstate = LS_PLAY;
    IPC->loop_length = loop_len;
    publish_diagnostic(1);
}

static void stop_loop(void) {
    if (lstate == LS_PLAY || lstate == LS_OD) fade_out_pending = 1;
    else { loop_len = 0; IPC->loop_length = 0; }
    lstate = LS_IDLE;
    IPC->loop_index = 0;
}

// -----------------------------------------------------------------------------
// Handler del paquete RX terminado
// -----------------------------------------------------------------------------
static void dma_handler(XAxiDma *dma) {
    static int rx_cur = 0;   // 0 = rx_ping armado, 1 = rx_pong armado

    u32 tx_irq = XAxiDma_IntrGetIrq(dma, XAXIDMA_DMA_TO_DEVICE);
    if (tx_irq & XAXIDMA_IRQ_ERROR_MASK) IPC->diag_dma_tx_errors++;
    if (tx_irq) XAxiDma_IntrAckIrq(dma, tx_irq, XAXIDMA_DMA_TO_DEVICE);

    u32 rx_irq = XAxiDma_IntrGetIrq(dma, XAXIDMA_DEVICE_TO_DMA);
    if (rx_irq & XAXIDMA_IRQ_ERROR_MASK) IPC->diag_dma_rx_errors++;
    XAxiDma_IntrAckIrq(dma, rx_irq, XAXIDMA_DEVICE_TO_DMA);
    if (!(rx_irq & XAXIDMA_IRQ_IOC_MASK)) return;

    // Rearmar RX con el otro buffer y quedarse con el que termino
    u32 *rx = rx_cur ? rx_pong : rx_ping;
    u32 *next = rx_cur ? rx_ping : rx_pong;
    start_dma(dma, (UINTPTR)next, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);
    rx_cur ^= 1;
    Xil_DCacheInvalidateRange((UINTPTR)rx, PACKET_SIZE * sizeof(u32));

    u32 j = rx_pkt++;

    // Medicion del intervalo entre IOCs (para detectar atrasos)
    XTime now;
    XTime_GetTime(&now);
    u64 gap = (last_ioc != 0) ? (u64)(now - last_ioc) : 0;
    last_ioc = now;
    if (gap > 0 && j > 4) {
        if (avg_gap == 0) avg_gap = gap;
        else if (gap < 2 * avg_gap) avg_gap = (avg_gap * 15 + gap) / 16;
    }
    if (tx_running && avg_gap != 0 && gap > (avg_gap * 9) / 5) {
        // Atraso mayor a ~1 paquete: el FIFO TX pudo vaciarse. Resincronizar.
        request_resync(now, 3 * avg_gap);
    }

    // (Re)sincronizacion del stream TX. Se hace al principio del handler para que
    // el desfase entre el comienzo del paquete RX j+1 y la primera palabra TX sea
    // minimo y constante (X_EST). El FIFO TX ya esta vacio (se dreno esperando
    // sync_after) y el IOC no es de un atraso acumulado (gap normal).
    int synced_now = 0;
    if (!tx_running && now >= sync_after && (avg_gap == 0 || gap >= avg_gap / 2)) {
        int ok = (queue_tx_packet(j + 1) == XST_SUCCESS);
        ok = ok && (queue_tx_packet(j + 2) == XST_SUCCESS);
        Xil_Out32(GPIO_MIXER_BASE + 0x00, MIXER_MODE_MIX);
        if (ok) { tx_running = 1; synced_now = 1; }
        else request_resync(now, avg_gap ? 3 * avg_gap : COUNTS_PER_SECOND / 10);
    }

    int req = IPC->hw_mode;

    // ---------------- Maquina de estados del looper ----------------
    switch (lstate) {
    case LS_IDLE:
        if (req == 1) {
            lstate = LS_REC;
            rec_len = 0;
            loop_len = 0;
            IPC->loop_length = 0;
            IPC->diag_record_us = 0;
            IPC->diag_recorded_words = 0;
            IPC->diag_stream_word_rate = 0;
            IPC->diag_seam_left = 0;
            IPC->diag_seam_right = 0;
            XTime_GetTime(&record_start_ticks);
        }
        break;
    default:
        break;
    }

    switch (lstate) {
    case LS_REC:
        if (req == 0) {                         // stop durante REC: descartar
            lstate = LS_IDLE;
            rec_len = 0;
        } else if (req == 1) {
            for (u32 i = 0; i < PACKET_SIZE; i++) LoopBuffer[rec_len + i] = rx[i];
            rec_len += PACKET_SIZE;
            IPC->loop_index = rec_len;
            if (rec_len + PACKET_SIZE > MAX_SAMPLES) {   // buffer lleno: pasar a PLAY
                IPC->hw_mode = 2;
                finish_recording();
            }
        } else {                                // 2 o 3: cerrar el loop
            finish_recording();
        }
        break;

    case LS_PLAY:
        if (req == 0) {
            stop_loop();
        } else if (req == 3 && loop_len >= MIN_OD_LEN) {
            lstate = LS_OD;
            od_first = 1;                       // se empieza a escribir en el proximo paquete
            od_words = 0;
            od_start_pos = tx_pos[(j + 1) & (POS_RING - 1)];
        }
        break;

    case LS_OD:
        if (req == 3) {
            overdub_write(rx, j, od_first ? 1 : 0);
            od_first = 0;
        } else {
            // Salida del overdub: este paquete todavia se grabo en OD -> fade-out
            if (!od_first) overdub_write(rx, j, -1);
            IPC->diag_overdub_words = od_words;
            IPC->diag_overdub_start_index = od_start_pos;
            IPC->diag_overdub_end_index = tx_pos[j & (POS_RING - 1)];
            publish_diagnostic(2);
            if (req == 0) stop_loop();
            else lstate = LS_PLAY;
        }
        break;

    default:
        break;
    }

    // Grabacion a SD (lo que suena)
    if (IPC->sd_recording == 1) {
        for (u32 i = 0; i < PACKET_SIZE; i++) {
            if (sd_length + i < MAX_SD_SAMPLES) SdRecordBuffer[sd_length + i] = rx[i];
        }
        sd_length += PACKET_SIZE;
    }

    // Posicion que se esta escuchando (para la barra de progreso)
    if (lstate == LS_PLAY || lstate == LS_OD) {
        u32 p = tx_pos[j & (POS_RING - 1)];
        if (p != POS_NONE) IPC->loop_index = p;
    }

    // ---------------- Stream TX ----------------
    if (sd_save_request && !sd_quiesced && quiesce_left == 0) quiesce_left = TX_AHEAD + 1;

    if (tx_running && !synced_now) {
        if (queue_tx_packet(j + TX_AHEAD) != XST_SUCCESS) {
            request_resync(now, avg_gap ? 3 * avg_gap : COUNTS_PER_SECOND / 10);
        } else if (quiesce_left > 0) {
            quiesce_left--;
            if (quiesce_left == 0) sd_quiesced = 1;   // FIFO TX lleno de ceros: se puede guardar
        }
    }
}

// --- SD CARD SAVE ---
#pragma pack(push, 1)
typedef struct {
    char riff_tag[4];
    u32  riff_length;
    char wave_tag[4];
    char fmt_tag[4];
    u32  fmt_length;
    u16  audio_format;
    u16  num_channels;
    u32  sample_rate;
    u32  byte_rate;
    u16  block_align;
    u16  bits_per_sample;
    char data_tag[4];
    u32  data_length;
} WavHeader; // header archivo WAV
#pragma pack(pop)

// Guarda el buffer en formato WAV en la SD sin sobrescribir el anterior
void SaveWavToSD(u32* buffer, u32 num_frames) {
    FIL wav_file;
    FRESULT res;
    UINT bytes_written;
    char filename[32];
    static int track_num = 1;
    FILINFO fno;

    while (1) {
        sprintf(filename, "0:/LOOP_%03d.WAV", track_num);
        if (f_stat(filename, &fno) != FR_OK) break;
        track_num++;
        if (track_num > 999) break;
    }
    res = f_open(&wav_file, filename, FA_CREATE_ALWAYS | FA_WRITE);
    if (res != FR_OK) return;

    u32 data_size = num_frames * 6;
    WavHeader header = {
        .riff_tag = {'R','I','F','F'},
        .riff_length = data_size + sizeof(WavHeader) - 8,
        .wave_tag = {'W','A','V','E'},
        .fmt_tag = {'f','m','t',' '},
        .fmt_length = 16,
        .audio_format = 1,
        .num_channels = 2,
        .sample_rate = 48000,
        .byte_rate = 48000 * 2 * 3,
        .block_align = 6,
        .bits_per_sample = 24,
        .data_tag = {'d','a','t','a'},
        .data_length = data_size
    };
    f_write(&wav_file, &header, sizeof(WavHeader), &bytes_written);

    static u8 pcm_buffer[6000];
    int pcm_idx = 0;
    for (u32 i = 0; i < num_frames; i++) {
        u32 sample = (buffer[i] >> 4) & 0xFFFFFF;
        pcm_buffer[pcm_idx++] = (u8)(sample & 0xFF);
        pcm_buffer[pcm_idx++] = (u8)((sample >> 8) & 0xFF);
        pcm_buffer[pcm_idx++] = (u8)((sample >> 16) & 0xFF);
        if (pcm_idx >= (int)sizeof(pcm_buffer)) {
            f_write(&wav_file, pcm_buffer, pcm_idx, &bytes_written);
            pcm_idx = 0;
        }
    }
    if (pcm_idx > 0) f_write(&wav_file, pcm_buffer, pcm_idx, &bytes_written);
    f_close(&wav_file);
}

static void handle_presets(void) {
    if (IPC->preset_cmd == 0) return;

    int cmd = IPC->preset_cmd;
    IPC->preset_status = 1; // BUSY

    if (cmd >= 1 && cmd <= 3) {
        char filename[32];
        sprintf(filename, "0:/PRESET_%d.BIN", cmd);
        FIL fil;
        if (f_open(&fil, filename, FA_CREATE_ALWAYS | FA_WRITE) == FR_OK) {
            UINT bw;
            int buf[6][4];
            for (int fx = 0; fx < 6; fx++)
                for (int p = 0; p < 4; p++) buf[fx][p] = IPC->preset_data[fx][p];
            f_write(&fil, buf, sizeof(buf), &bw);
            f_close(&fil);
            IPC->preset_status = 2; // OK
        } else {
            IPC->preset_status = 3; // ERROR
        }
    } else if (cmd >= 4 && cmd <= 6) {
        char filename[32];
        sprintf(filename, "0:/PRESET_%d.BIN", cmd - 3);
        FIL fil;
        if (f_open(&fil, filename, FA_READ) == FR_OK) {
            UINT br;
            int buf[6][4];
            f_read(&fil, buf, sizeof(buf), &br);
            f_close(&fil);
            for (int fx = 0; fx < 6; fx++)
                for (int p = 0; p < 4; p++) IPC->preset_data[fx][p] = buf[fx][p];
            IPC->preset_status = 2; // OK
        } else {
            IPC->preset_status = 3; // ERROR
        }
    }
    IPC->preset_cmd = 0;
}

int main() {
    Xil_SetTlbAttributes(0xFFFF0000, 0x14de2);
    IPC->preset_cmd = 0;   // descartar basura de la OCM al arrancar
    IPC->diag_sequence = 0;
    IPC->diag_event = 0;
    IPC->diag_record_us = 0;
    IPC->diag_recorded_words = 0;
    IPC->diag_stream_word_rate = 0;
    IPC->diag_seam_left = 0;
    IPC->diag_seam_right = 0;
    IPC->diag_record_saturated = 0;
    IPC->diag_overdub_words = 0;
    IPC->diag_overdub_changed = 0;
    IPC->diag_overdub_max_delta = 0;
    IPC->diag_overdub_saturated = 0;
    IPC->diag_dma_rx_errors = 0;
    IPC->diag_dma_tx_errors = 0;
    IPC->diag_transfer_errors = 0;
    IPC->diag_record_same_prev2 = 0;
    IPC->diag_record_compared = 0;
    IPC->diag_overdub_mean_delta = 0;
    IPC->diag_overdub_large_delta = 0;
    IPC->diag_overdub_start_index = 0;
    IPC->diag_overdub_end_index = 0;
    IPC->diag_overdub_max_index = 0;
    IPC->diag_start_rx_errors = 0;
    IPC->diag_start_tx_errors = 0;
    IPC->diag_resyncs = 0;

    for (int i = 0; i < POS_RING; i++) tx_pos[i] = POS_NONE;

    static FATFS fs;       // fuera del stack
    f_mount(&fs, "0:/", 1);

    XAxiDma_Config *CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
    XAxiDma_CfgInitialize(&AxiDma, CfgPtr);

    // Habilitar la generacion de banderas de estado en el DMA (se consultan por polling)
    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK, XAXIDMA_DMA_TO_DEVICE);

    // Configurar IP I2S
    Xil_Out32(I2S_RX_BASE + 0x20, 0x00000002);
    Xil_Out32(I2S_TX_BASE + 0x20, 0x00000002);
    Xil_Out32(I2S_TX_BASE + 0x0C, 0x00000001);
    Xil_Out32(I2S_RX_BASE + 0x30, 0x00000001);
    Xil_Out32(I2S_TX_BASE + 0x30, 0x00000001);

    // Mezclador en modo mezcla desde el arranque (con FIFO TX vacio solo pasa el vivo)
    Xil_Out32(GPIO_MIXER_BASE + 0x00, MIXER_MODE_MIX);

    // Encender modulos I2S
    Xil_Out32(I2S_TX_BASE + 0x08, 0x00000001);
    Xil_Out32(I2S_RX_BASE + 0x08, 0x00000001);

    // Iniciar el DMA de entrada (RX). El TX se sincroniza en el primer IOC.
    start_dma(&AxiDma, (UINTPTR)rx_ping, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);

    // Enviar OK al core 0
    IPC->core1_ready = 1;

    static int was_sd_recording = 0;

    while (1) {
        // Polling del DMA (sin usleep: el IOC se atiende apenas aparece)
        u32 rx_sr = XAxiDma_IntrGetIrq(&AxiDma, XAXIDMA_DEVICE_TO_DMA);
        if (rx_sr & (XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK)) {
            dma_handler(&AxiDma);
        }

        // Grabacion a SD
        if (IPC->sd_recording == 1 && was_sd_recording == 0) {
            sd_length = 0;
            was_sd_recording = 1;
        } else if (IPC->sd_recording == 0 && was_sd_recording == 1) {
            sd_save_request = 1;            // el handler encola ceros y avisa
            was_sd_recording = 0;
        }

        if (sd_save_request && sd_quiesced) {
            SaveWavToSD(SdRecordBuffer, sd_length);   // bloquea: el audio se corta mientras guarda
            sd_save_request = 0;
            sd_quiesced = 0;
            XTime t;
            XTime_GetTime(&t);
            request_resync(t, avg_gap ? 3 * avg_gap : COUNTS_PER_SECOND / 10);
        }

        // Presets en SD (cortos). Si tardan mas de un paquete, el handler resincroniza solo.
        handle_presets();
    }
    return 0;
}
