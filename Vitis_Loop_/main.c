#include "xparameters.h"    // Contiene las direcciones de memoria (Base Addresses)
#include "xaxidma.h"       // Driver DMA
#include "xscugic.h"       // Driver interrupciones
#include "xil_printf.h"    // Consola
#include "xil_io.h"        // Necesario para Xil_Out32 y Xil_In32
#include "xil_cache.h"     // Funciones de caché

// Es recomendable buscar la direccion base en xparameters.h, 
// pero si es constante en tu diseño de Vivado, esto es valido.
#define I2S_TX_ADDR  0x43C00000 // Dirección que viene de Vivado

// Instancia global del controlador DMA
XAxiDma AxiDma;

// ATENCION: Para CO-SIMULACION o EMULACION, usar un valor pequeño (ej. 16 o 32).
// usar 1024 para arrib apara hardware real. ACORDARSE DE CAMBIARLO EN VIVADO
#define MAX_PKT_LEN 16
u8 RxBuffer[MAX_PKT_LEN] __attribute__((aligned(32))); // Alinear a la línea de caché

int main()
{
    int Status;
    XAxiDma_Config *Config;

    xil_printf("\r\n--- Iniciando Sistema I2S y DMA ---\r\n");

    // 1. Inicializar el DMA
    Config = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_BASEADDR);
    if (!Config) {
        xil_printf("Error: No se encontro la configuracion del DMA.\r\n");
        return XST_FAILURE;
    }

    Status = XAxiDma_CfgInitialize(&AxiDma, Config);
    if (Status != XST_SUCCESS) {
        xil_printf("Error: Fallo la inicializacion del DMA.\r\n");
        return XST_FAILURE;
    }

    // 2. Para habilitar el transmisor/receptor I2S:
    Xil_Out32(I2S_TX_ADDR + 0x00, 0x1); // Escribimos un '1' en el registro de control
    
    // 3. Programar el DMA para recibir un bloque de muestras (Modo S2MM)
    // XAXIDMA_DEVICE_TO_DMA indica la direccion (Hardware -> Memoria)
    Status = XAxiDma_SimpleTransfer(&AxiDma, (u32)RxBuffer, MAX_PKT_LEN, XAXIDMA_DEVICE_TO_DMA);
    if (Status != XST_SUCCESS) {
        xil_printf("Error configurando la transferencia DMA.\r\n");
        return XST_FAILURE;
    }

    // 4. Esperar a que la transferencia DMA termine (Polling)
    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA)) {
        // Esperando a que el DMA termine la transferencia a memoria...
    }

    // 5. Invalidar la caché para que la CPU lea los datos reales de la memoria RAM
    Xil_DCacheInvalidateRange((INTPTR)RxBuffer, MAX_PKT_LEN);

    xil_printf("Transferencia DMA completada con exito.\r\n");

    return 0;
}