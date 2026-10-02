#include <stdio.h>
#include "xparameters.h"
#include "xscutimer.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "ff.h"
#include "sleep.h"
#include "xil_mmu.h"
#include "ipc.h"

#define DMA_DEV_ID          XPAR_XAXIDMA_0_BASEADDR
#define PACKET_SIZE         512     // Muestras por paquete DMA
#define MAX_SAMPLES         1440000 // Memoria Looper (30s aprox)
#define MAX_SD_SAMPLES      (48000 * 300) 

XAxiDma AxiDma;     
XScuTimer ScuTimer; 
// Buffers
u32 rx_ping[PACKET_SIZE] __attribute__((aligned(32)));
u32 rx_pong[PACKET_SIZE] __attribute__((aligned(32)));
u32 tx_ping[PACKET_SIZE] __attribute__((aligned(32)));
u32 tx_pong[PACKET_SIZE] __attribute__((aligned(32)));

u32 LoopBuffer[MAX_SAMPLES] __attribute__((aligned(32)));
u32 SdRecordBuffer[MAX_SD_SAMPLES] __attribute__((aligned(32)));

volatile u32 sd_length = 0;

#define I2S_RX_BASE     0x43C00000
#define I2S_TX_BASE     0x43C10000
#define GPIO_MIXER_BASE 0x41200000

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

    // Revisa que nombres estÃ¡n tomados y escribe el siguiente
    while (1) {
        sprintf(filename, "0:/LOOP_%03d.WAV", track_num);
        if (f_stat(filename, &fno) != FR_OK) {
            break;
        }
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

    u8 pcm_buffer[6000];
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

// ---------------------------------------------------------
// Handler DMA
// ---------------------------------------------------------
static void dma_handler(void *CallbackRef) {
    static int ping_pong_state = 0; // 0 = Ping, 1 = Pong
    static int prev_hw_mode = 0;
    
    // polling de los registros de interrupciÃºn del DMA (arriba cuando termina de transmitir)
    // NO ES TÃ‰CNICAMENTE "POR INTERRUPCIÃ“N" PERO ESTA FUNCIÃ“N FUNCIONA COMO ISR
    XAxiDma *AxiDmaInst = (XAxiDma *)CallbackRef; 

    u32 TxIrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE);
    if (TxIrqStatus) {
        XAxiDma_IntrAckIrq(AxiDmaInst, TxIrqStatus, XAXIDMA_DMA_TO_DEVICE);
    }
    u32 IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DEVICE_TO_DMA);
    if (!(IrqStatus & XAXIDMA_IRQ_IOC_MASK)) return; //chequea devuelta que haya terminado el RX (solo depende de RX, no TX)
    int hw_mode = IPC->hw_mode;

    // MÃQUINA DE ESTADOS
    //Revisa hw_mode. Si se pasÃ³ de IDLE a REC (Grabar), reinicia el Ã­ndice del Looper
    //Si pasÃ³ de REC a PLAY (Reproducir), fija el tamaÃ±o de bucle actual y empieza la salida TX DMA.
    if (hw_mode == 1 && prev_hw_mode == 0) {
        IPC->loop_index = 0; // IDLE -> REC
    } else if (hw_mode == 2 && prev_hw_mode == 1) {
        IPC->loop_length = IPC->loop_index; // REC -> PLAY
        IPC->loop_index = 0;
        
        //inyecta el primer paquete TX
        if (IPC->loop_length > 0) {
            for(int i=0; i<PACKET_SIZE; i++) {
                tx_ping[i] = LoopBuffer[i % IPC->loop_length];
                tx_pong[i] = LoopBuffer[(PACKET_SIZE + i) % IPC->loop_length];
            }
            Xil_DCacheFlushRange((UINTPTR)tx_ping, PACKET_SIZE * sizeof(u32));
            Xil_DCacheFlushRange((UINTPTR)tx_pong, PACKET_SIZE * sizeof(u32));
            XAxiDma_SimpleTransfer(AxiDmaInst, (UINTPTR)tx_ping, PACKET_SIZE * sizeof(u32), XAXIDMA_DMA_TO_DEVICE);
        }
    }
    prev_hw_mode = hw_mode;

    if (ping_pong_state == 0) {  
        // === MITAD PING ===
        //se enciende el dma apuntando a rx pong (DEVICE_TO_DMA)
        XAxiDma_SimpleTransfer(AxiDmaInst, (UINTPTR)rx_pong, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);
        
        //si es play o overdub, se enciende el dma apuntando a tx pong (DMA_TO_DEVICE)
        if (hw_mode == 2 || hw_mode == 3) {
            while (XAxiDma_Busy(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE)) { usleep(1); }
            XAxiDma_SimpleTransfer(AxiDmaInst, (UINTPTR)tx_pong, PACKET_SIZE * sizeof(u32), XAXIDMA_DMA_TO_DEVICE);
        }
        // invalida rx_ping anterior para que el procesador pueda leerlo
        Xil_DCacheInvalidateRange((UINTPTR)rx_ping, PACKET_SIZE * sizeof(u32));

        //guarda el buffer rx_ping en el buffer del loop si estÃ¡ en PASTHROUGH o PLAY
        if (hw_mode == 1 || hw_mode == 3) {
            for(int i=0; i<PACKET_SIZE; i++) {
                if (IPC->loop_index + i < MAX_SAMPLES) LoopBuffer[IPC->loop_index + i] = rx_ping[i];
            }
        }
        //guarda el buffer rx_ping en el buffer de la sd si estÃ¡ grabando
        if (IPC->sd_recording == 1) {
            for(int i=0; i<PACKET_SIZE; i++) {
                if (sd_length + i < MAX_SD_SAMPLES) SdRecordBuffer[sd_length + i] = rx_ping[i];
            }
            sd_length += PACKET_SIZE;
        }

        //se corre el indice del loop (siempre)
        IPC->loop_index += PACKET_SIZE;
        if (hw_mode != 1 && IPC->loop_length > 0) IPC->loop_index %= IPC->loop_length;

        //prepara el siguiente paquete TX (play y overdub)
        if (hw_mode == 2 || hw_mode == 3) {
            u32 tx_idx = (IPC->loop_index + PACKET_SIZE) % IPC->loop_length;
            for(int i=0; i<PACKET_SIZE; i++) {
                tx_ping[i] = LoopBuffer[tx_idx++];
                if (tx_idx >= IPC->loop_length) tx_idx = 0;
            }
            Xil_DCacheFlushRange((UINTPTR)tx_ping, PACKET_SIZE * sizeof(u32));
        }
        ping_pong_state = 1;
    } else { 
        // === MITAD PONG === (igual al ping)
        XAxiDma_SimpleTransfer(AxiDmaInst, (UINTPTR)rx_ping, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);
        
        if (hw_mode == 2 || hw_mode == 3) {
            while (XAxiDma_Busy(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE)) { usleep(1); }
            XAxiDma_SimpleTransfer(AxiDmaInst, (UINTPTR)tx_ping, PACKET_SIZE * sizeof(u32), XAXIDMA_DMA_TO_DEVICE);
        }

        Xil_DCacheInvalidateRange((UINTPTR)rx_pong, PACKET_SIZE * sizeof(u32));

        if (hw_mode == 1 || hw_mode == 3) {
            for(int i=0; i<PACKET_SIZE; i++) {
                if (IPC->loop_index + i < MAX_SAMPLES) LoopBuffer[IPC->loop_index + i] = rx_pong[i];
            }
        }

        if (IPC->sd_recording == 1) {
            for(int i=0; i<PACKET_SIZE; i++) {
                if (sd_length + i < MAX_SD_SAMPLES) SdRecordBuffer[sd_length + i] = rx_pong[i];
            }
            sd_length += PACKET_SIZE;
        }

        IPC->loop_index += PACKET_SIZE;
        if (hw_mode != 1 && IPC->loop_length > 0) IPC->loop_index %= IPC->loop_length;

        if (hw_mode == 2 || hw_mode == 3) {
            u32 tx_idx = (IPC->loop_index + PACKET_SIZE) % IPC->loop_length;
            for(int i=0; i<PACKET_SIZE; i++) {
                tx_pong[i] = LoopBuffer[tx_idx++];
                if (tx_idx >= IPC->loop_length) tx_idx = 0;
            }
            Xil_DCacheFlushRange((UINTPTR)tx_pong, PACKET_SIZE * sizeof(u32));
        }
        ping_pong_state = 0;
    }
}


int main() {
    Xil_SetTlbAttributes(0xFFFF0000, 0x14de2);

    FATFS fs;
    f_mount(&fs, "0:/", 1);

    XAxiDma_Config *CfgPtr = XAxiDma_LookupConfig(DMA_DEV_ID);
    XAxiDma_CfgInitialize(&AxiDma, CfgPtr);

    // Habilitar la generaciÃ³n de banderas de estado en el DMA
    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK, XAXIDMA_DMA_TO_DEVICE);

    //Configurar IP I2S
    Xil_Out32(I2S_RX_BASE + 0x20, 0x00000002);
    Xil_Out32(I2S_TX_BASE + 0x20, 0x00000002);
    Xil_Out32(I2S_TX_BASE + 0x0C, 0x00000001); 
    Xil_Out32(I2S_RX_BASE + 0x30, 0x00000001); 
    Xil_Out32(I2S_TX_BASE + 0x30, 0x00000001); 

    //Encender modulos I2S
    Xil_Out32(I2S_TX_BASE + 0x08, 0x00000001);
    Xil_Out32(I2S_RX_BASE + 0x08, 0x00000001);

    // Iniciar el motor de DMA de Entrada (RX)
    XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)rx_ping, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);


    // Enviar OK al core 0
    IPC->core1_ready = 1;

    static int was_sd_recording = 0;

    while (1) {
        //polling del dma
        u32 rx_sr = XAxiDma_IntrGetIrq(&AxiDma, XAXIDMA_DEVICE_TO_DMA);
        u32 tx_sr = XAxiDma_IntrGetIrq(&AxiDma, XAXIDMA_DMA_TO_DEVICE);

        if (rx_sr & XAXIDMA_IRQ_IOC_MASK) {
            dma_handler(&AxiDma);
        }

        usleep(100);

        //leer modo desde nucleo 0 (UI)
        int current_mode = IPC->hw_mode;
        
        //Mandar modo a PL
        Xil_Out32(GPIO_MIXER_BASE + 0x00, current_mode);

        // Detectar guardado a SD ON
        if (IPC->sd_recording == 1 && was_sd_recording == 0) {
            sd_length = 0;
            was_sd_recording = 1;
        } else if (IPC->sd_recording == 0 && was_sd_recording == 1) {
            XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA); // Se desactiva el DMA antes de guardar
            SaveWavToSD(SdRecordBuffer, sd_length);
            XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK, XAXIDMA_DEVICE_TO_DMA);
            XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)rx_ping, PACKET_SIZE * sizeof(u32), XAXIDMA_DEVICE_TO_DMA);
            was_sd_recording = 0;
        }

        // Manejo de Presets en SD
        if (IPC->preset_cmd != 0) {
            int cmd = IPC->preset_cmd;
            IPC->preset_status = 1; // BUSY
            
            if (cmd >= 1 && cmd <= 3) {
                int slot = cmd;
                char filename[32];
                sprintf(filename, "0:/PRESET_%d.BIN", slot);
                
                FIL fil;
                FRESULT res = f_open(&fil, filename, FA_CREATE_ALWAYS | FA_WRITE);
                if (res == FR_OK) {
                    UINT bw;
                    int buf[6][4];
                    for(int fx=0; fx<6; fx++) {
                        for(int p=0; p<4; p++) {
                            buf[fx][p] = IPC->preset_data[fx][p];
                        }
                    }
                    f_write(&fil, buf, sizeof(buf), &bw);
                    f_close(&fil);
                    IPC->preset_status = 2; // OK
                } else {
                    IPC->preset_status = 3; // ERROR
                }
            } else if (cmd >= 4 && cmd <= 6) {
                int slot = cmd - 3;
                char filename[32];
                sprintf(filename, "0:/PRESET_%d.BIN", slot);
                
                FIL fil;
                FRESULT res = f_open(&fil, filename, FA_READ);
                if (res == FR_OK) {
                    UINT br;
                    int buf[6][4];
                    f_read(&fil, buf, sizeof(buf), &br);
                    f_close(&fil);
                    for(int fx=0; fx<6; fx++) {
                        for(int p=0; p<4; p++) {
                            IPC->preset_data[fx][p] = buf[fx][p];
                        }
                    }
                    IPC->preset_status = 2; // OK
                } else {
                    IPC->preset_status = 3; // ERROR
                }
            }
            IPC->preset_cmd = 0;
        }
        
    }
    return 0;
}
