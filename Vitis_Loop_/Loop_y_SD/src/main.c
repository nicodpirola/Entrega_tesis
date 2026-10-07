/* El mezclador del PL (axi_stream_looper_mixer) queda SIEMPRE en modo mezcla del audio vivo + RAM.
 El TX corre siempre. Envía info en PAY/OVERDUB o ceros en IDLE/REC. Vivo + 0 = vivo, asi que en IDLE/REC se
 escucha lo mismo que antes.

 Esto se decidió para poder implementar un sistema que tenga atenuaciones
 para evitar artefactos de audio.

 Convencion de indices:
   j = numero del paquete RX que acaba de terminar (IOC).
   El paquete TX encolado en el IOC j se mezcla durante el paquete RX
  j + TX_AHEAD. La palabra TX arranca X_EST palabras despues del inicio del
   paquete RX (latencia del handler al sincronizar).
*/
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
#define PACKET_SIZE         512 // muestras por paquete
#define MAX_SAMPLES         1440000 //  max muestras en el loop (30 segs)
#define MAX_SD_SAMPLES      (48000 * 300)

#define TX_AHEAD            2 // paquetes de anticipación del TX (latencia total)
#define X_EST               2 // palabras desfase TX/RX 
#define FADE_WORDS          256
#define MIN_OD_LEN          (4 * PACKET_SIZE)
#define POS_NONE            0xFFFFFFFFu
#define POS_RING            8
#define TX_BUFS             4

#define I2S_RX_BASE         0x43C00000
#define I2S_TX_BASE         0x43C10000
#define GPIO_MIXER_BASE     0x41200000
#define MIXER_MODE_MIX      2u // modo mezcla fijo


XAxiDma AxiDma;
XScuTimer ScuTimer;

// Buffers DMA
u32 rx_ping[PACKET_SIZE] __attribute__((aligned(32))); // RX
u32 rx_pong[PACKET_SIZE] __attribute__((aligned(32)));
static u32 tx_buf[TX_BUFS][PACKET_SIZE] __attribute__((aligned(32))); //TX
// Buffers de guardado (grandes)
u32 LoopBuffer[MAX_SAMPLES + PACKET_SIZE] __attribute__((aligned(32)));
u32 SdRecordBuffer[MAX_SD_SAMPLES] __attribute__((aligned(32)));

volatile u32 sd_length = 0;

static hw_mode_t lstate = HW_MODE_IDLE;
static u32 loop_len = 0; //largo del loop en # de muestras (n*PACKET_SIZE) 
static u32 rec_len = 0;  //largo de la grabacion
static u32 play_pos = 0;   //próximo paquete a enviar por TX
static u32 tx_pos[POS_RING]; // índice para determinar progreso de la barra en interfaz
static u32 rx_pkt = 0; // n de paquete TX que terminó
static int fade_out_pending = 0; 
static int od_first = 0;  // primer paquete del overdub
static int tx_buf_idx = 0; 

static int tx_running = 0;
static XTime sync_after = 0; // tiempo de espera seteado en resincronización
static XTime last_ioc = 0;
static u64 avg_gap = 0; // promedio de intervalo entre IOC usado para detectar desincronizaciones

static volatile int sd_save_request = 0;
static volatile int sd_quiesced = 0;
static int quiesce_left = 0;
//
// Operaciones de muestras
//
static inline int32_t word_audio(u32 w) { // I2S a int32
    return ((int32_t)(w << 4)) >> 8;
}
static inline u32 audio_word(int32_t a) { // int32 a I2S
    return ((u32)a & 0x00FFFFFFu) << 4;
}
static inline int32_t lerp_audio(int32_t a, int32_t b, u32 w, u32 den) { // mezcla lineal;
    return a + (int32_t)(((s64)(b - a) * (s64)w) / (s64)den);
}
static inline int start_dma(XAxiDma *dma, UINTPTR address, u32 bytes, int direction) {
    return XAxiDma_SimpleTransfer(dma, address, bytes, direction);
}

static int wait_tx_idle(XAxiDma *dma) {
    XTime t0, t;
    XTime_GetTime(&t0);
    while (XAxiDma_Busy(dma, XAXIDMA_DMA_TO_DEVICE)) {
        XTime_GetTime(&t);
        if ((t - t0) > (COUNTS_PER_SECOND / 500)) return 0;
    }
    return 1;
}

//
// Armado paquetes TX
//
static void fill_from_loop(u32 *dst, u32 pos, int fade_out) {
    for (u32 i = 0; i < PACKET_SIZE; i++) {
        u32 p = pos + i;
        if (p >= loop_len) p -= loop_len;
        u32 w = LoopBuffer[p];
        if (fade_out && i >= PACKET_SIZE - FADE_WORDS) {
            u32 k = PACKET_SIZE - 1 - i;
            w = audio_word(lerp_audio(0, word_audio(w), k, FADE_WORDS));
        }
        dst[i] = w;
    }
}

static void request_resync(XTime now, u64 delay) {
    tx_running = 0;
    sync_after = now + delay;
    for (int i = 0; i < POS_RING; i++) tx_pos[i] = POS_NONE;
}

static int queue_tx_packet(u32 jq) {
    u32 *buf = tx_buf[tx_buf_idx];
    tx_buf_idx = (tx_buf_idx + 1) % TX_BUFS;
    u32 slot = jq & (POS_RING - 1);

    int playing = (lstate == HW_MODE_PLAY || lstate == HW_MODE_OD) && loop_len > 0 && quiesce_left == 0;

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
    wait_tx_idle(&AxiDma);
    return start_dma(&AxiDma, (UINTPTR)buf, PACKET_SIZE * sizeof(u32), XAXIDMA_DMA_TO_DEVICE);
}

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
    }
}

static void finish_recording(void) {
    if (rec_len < MIN_OD_LEN) {
        lstate = HW_MODE_IDLE;
        loop_len = 0;
        IPC->hw_mode = HW_MODE_IDLE;
        IPC->loop_length = 0;
        return;
    }

    loop_len = rec_len;

    for (u32 i = 0; i < FADE_WORDS; i++) {
        LoopBuffer[i] = audio_word(lerp_audio(0, word_audio(LoopBuffer[i]), i, FADE_WORDS));
        u32 e = loop_len - 1 - i;
        LoopBuffer[e] = audio_word(lerp_audio(0, word_audio(LoopBuffer[e]), i, FADE_WORDS));
    }

    play_pos = 0;
    lstate = HW_MODE_PLAY;
    IPC->loop_length = loop_len;
}

static void stop_loop(void) {
    if (lstate == HW_MODE_PLAY || lstate == HW_MODE_OD) fade_out_pending = 1;
    else { loop_len = 0; IPC->loop_length = 0; }
    lstate = HW_MODE_IDLE;
    IPC->loop_index = 0;
}

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
} WavHeader;
#pragma pack(pop)

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

static void dma_handler(XAxiDma *dma) {
    static int rx_cur = 0;

    u32 tx_irq = XAxiDma_IntrGetIrq(dma, XAXIDMA_DMA_TO_DEVICE);
    if (tx_irq) XAxiDma_IntrAckIrq(dma, tx_irq, XAXIDMA_DMA_TO_DEVICE);

    u32 rx_irq = XAxiDma_IntrGetIrq(dma, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrAckIrq(dma, rx_irq, XAXIDMA_DEVICE_TO_DMA);
    if (!(rx_irq & XAXIDMA_IRQ_IOC_MASK)) return;

    u32 *rx = rx_cur ? rx_pong : rx_ping;
    u32 *next = rx_cur ? rx_ping : rx_pong;
    start_dma(dma, (UINTPTR)next, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);
    rx_cur ^= 1;
    Xil_DCacheInvalidateRange((UINTPTR)rx, PACKET_SIZE * sizeof(u32));

    u32 j = rx_pkt++;

    XTime now;
    XTime_GetTime(&now);
    u64 gap = (last_ioc != 0) ? (u64)(now - last_ioc) : 0; // calculo gap
    last_ioc = now;
    if (gap > 0 && j > 4) { // calculo promedio movil gap
        if (avg_gap == 0) avg_gap = gap;
        else if (gap < 2 * avg_gap) avg_gap = (avg_gap * 15 + gap) / 16;
    }
    if (tx_running && avg_gap != 0 && gap > (avg_gap * 9) / 5) { // se llama al rexync en casod e underflow
        request_resync(now, 3 * avg_gap);
    }
    int synced_now = 0;

    if (!tx_running && now >= sync_after && (avg_gap == 0 || gap >= avg_gap / 2)) { // fallo de armado de buffers
        int ok = (queue_tx_packet(j + 1) == XST_SUCCESS); // pide los 2 paquetes siguientes
        ok = ok && (queue_tx_packet(j + 2) == XST_SUCCESS);
        Xil_Out32(GPIO_MIXER_BASE + 0x00, MIXER_MODE_MIX);
        if (ok) { tx_running = 1; synced_now = 1; }
        else request_resync(now, avg_gap ? 3 * avg_gap : COUNTS_PER_SECOND / 10); // si no se peude llama a resync
    }

    hw_mode_t req = IPC->hw_mode;

    switch (lstate) {
    case HW_MODE_IDLE:
        if (req == HW_MODE_REC) {
            lstate = HW_MODE_REC;
            rec_len = 0;
            loop_len = 0;
            IPC->loop_length = 0;
        }
        break;

    case HW_MODE_REC:
        if (req == HW_MODE_IDLE) {
            lstate = HW_MODE_IDLE;
            rec_len = 0;
        } else if (req == HW_MODE_REC) {
            for (u32 i = 0; i < PACKET_SIZE; i++) LoopBuffer[rec_len + i] = rx[i];
            rec_len += PACKET_SIZE;
            IPC->loop_index = rec_len;
            if (rec_len + PACKET_SIZE > MAX_SAMPLES) {
                IPC->hw_mode = HW_MODE_PLAY;
                finish_recording();
            }
        } else {
            finish_recording();
        }
        break;

    case HW_MODE_PLAY:
        if (req == HW_MODE_IDLE) {
            stop_loop();
        } else if (req == HW_MODE_OD && loop_len >= MIN_OD_LEN) {
            lstate = HW_MODE_OD;
            od_first = 1;
        }
        break;

    case HW_MODE_OD:
        if (req == HW_MODE_OD) {
            overdub_write(rx, j, od_first ? 1 : 0);
            od_first = 0;
        } else {
            if (!od_first) overdub_write(rx, j, -1);
            if (req == HW_MODE_IDLE) stop_loop();
            else lstate = HW_MODE_PLAY;
        }
        break;
    }

    if (IPC->sd_recording == 1) {
        for (u32 i = 0; i < PACKET_SIZE; i++) {
            if (sd_length + i < MAX_SD_SAMPLES) SdRecordBuffer[sd_length + i] = rx[i];
        }
        sd_length += PACKET_SIZE;
    }

    if (lstate == HW_MODE_PLAY || lstate == HW_MODE_OD) {
        u32 p = tx_pos[j & (POS_RING - 1)];
        if (p != POS_NONE) IPC->loop_index = p;
    }

    if (sd_save_request && !sd_quiesced && quiesce_left == 0) quiesce_left = TX_AHEAD + 1;

    if (tx_running && !synced_now) {
        if (queue_tx_packet(j + TX_AHEAD) != XST_SUCCESS) {
            request_resync(now, avg_gap ? 3 * avg_gap : COUNTS_PER_SECOND / 10);
        } else if (quiesce_left > 0) {
            quiesce_left--;
            if (quiesce_left == 0) sd_quiesced = 1;
        }
    }
}

static void handle_presets(void) {
    if (IPC->preset_cmd == 0) return;

    int cmd = IPC->preset_cmd;
    IPC->preset_status = 1;

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
            IPC->preset_status = 2;
        } else {
            IPC->preset_status = 3;
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
            IPC->preset_status = 2;
        } else {
            IPC->preset_status = 3;
        }
    }
    IPC->preset_cmd = 0;
}

int main() {
    Xil_SetTlbAttributes(0xFFFF0000, 0x14de2);
    IPC->preset_cmd = 0;

    for (int i = 0; i < POS_RING; i++) tx_pos[i] = POS_NONE;

    static FATFS fs;
    f_mount(&fs, "0:/", 1);

    XAxiDma_Config *CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
    XAxiDma_CfgInitialize(&AxiDma, CfgPtr);

    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK, XAXIDMA_DMA_TO_DEVICE);

    Xil_Out32(I2S_RX_BASE + 0x20, 0x00000002);
    Xil_Out32(I2S_TX_BASE + 0x20, 0x00000002);
    Xil_Out32(I2S_TX_BASE + 0x0C, 0x00000001);
    Xil_Out32(I2S_RX_BASE + 0x30, 0x00000001);
    Xil_Out32(I2S_TX_BASE + 0x30, 0x00000001);

    Xil_Out32(GPIO_MIXER_BASE + 0x00, MIXER_MODE_MIX);

    Xil_Out32(I2S_TX_BASE + 0x08, 0x00000001);
    Xil_Out32(I2S_RX_BASE + 0x08, 0x00000001);

    start_dma(&AxiDma, (UINTPTR)rx_ping, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);

    IPC->core1_ready = 1;

    static int was_sd_recording = 0;

    while (1) {
        u32 rx_sr = XAxiDma_IntrGetIrq(&AxiDma, XAXIDMA_DEVICE_TO_DMA);
        if (rx_sr & (XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK)) {
            dma_handler(&AxiDma);
        }

        if (IPC->sd_recording == 1 && was_sd_recording == 0) {
            sd_length = 0;
            was_sd_recording = 1;
        } else if (IPC->sd_recording == 0 && was_sd_recording == 1) {
            sd_save_request = 1;
            was_sd_recording = 0;
        }

        if (sd_save_request && sd_quiesced) {
            SaveWavToSD(SdRecordBuffer, sd_length);
            sd_save_request = 0;
            sd_quiesced = 0;
            XTime t;
            XTime_GetTime(&t);
            request_resync(t, avg_gap ? 3 * avg_gap : COUNTS_PER_SECOND / 10);
        }

        handle_presets();
    }
    return 0;
}
