`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.03.2026 23:52:01
// Design Name: 
// Module Name: tb_zynq
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module tb_zynq();

    // Señales básicas (si tienes puertos externos en tu Block Design)
    // Puertos DDR (Manejados por la simulación VIP del Zynq)
    wire [14:0] DDR_addr;
    wire [2:0]  DDR_ba;
    wire        DDR_cas_n;
    wire        DDR_ck_n;
    wire        DDR_ck_p;
    wire        DDR_cke;
    wire        DDR_cs_n;
    wire [3:0]  DDR_dm;
    wire [31:0] DDR_dq;
    wire [3:0]  DDR_dqs_n;
    wire [3:0]  DDR_dqs_p;
    wire        DDR_odt;
    wire        DDR_ras_n;
    wire        DDR_reset_n;
    wire        DDR_we_n;

    // Puertos FIXED IO (Manejados por la simulación VIP del Zynq)
    wire        FIXED_IO_ddr_vrn;
    wire        FIXED_IO_ddr_vrp;
    wire [53:0] FIXED_IO_mio;
    wire        FIXED_IO_ps_clk;
    wire        FIXED_IO_ps_porb;
    wire        FIXED_IO_ps_srstb;

    logic ps_clk_generator; // Generador de reloj para el PS
    logic ps_porb_generator; // Generador de PORB
    logic ps_srstb_generator; // Generador de SRSTB
    logic sys_clock;        // Reloj de sistema (generado por el TB)

    wire sclk_out_0; // Reloj de bits I2S (equivalente a BCLK)
    wire lrclk_out_0; // Reloj de canal I2S (equivalente a LRCLK)
    wire sclk_out_1;
    wire lrclk_out_1;
    wire mclk_out_adc;
    wire mclk_out_dac;
    logic sdata_0_in_0; // Datos hacia el FPGA (generados por el emulador del TB)
    logic sdata_0_in_reg; // Registro en posedge BCLK (evita carrera con el muestreo del IP)
    wire sdata_0_out_0; // Datos desde el FPGA hacia el exterior
    logic pedal_in_0 = 1'b1; // (DEPRECADO) Se mantiene para no romper el port map del wrapper

    // Instancia del wrapper de tu Block Design
    // NOTA: Cambia "design_1_wrapper" por el nombre real de tu wrapper
    design_1_wrapper dut (
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .sys_clock(sys_clock),
        .sclk_out_0(sclk_out_0),
        .lrclk_out_0(lrclk_out_0),
        .sclk_out_1(sclk_out_1),
        .lrclk_out_1(lrclk_out_1),
        .mclk_out_adc(mclk_out_adc),
        .mclk_out_dac(mclk_out_dac),
        .sdata_0_in_0(sdata_0_in_0),
        .sdata_0_out_0(sdata_0_out_0),
        .pedal_in_0(pedal_in_0)
    );

    // Variable para capturar la respuesta del bus AXI (0 = OK)
    bit [1:0] resp;
    bit [31:0] read_data; // Para leer la memoria RAM al final

    // =========================================================================
    // Emulador de Fuente de Audio I2S (ADC) — master en el DUT (BCLK/LRCLK)
    // =========================================================================
    // IP C_DWIDTH=24, C_32BIT_LR=1: slot de 32 BCLK = 24 bits PCM MSB-first + 8 ciclos pad 0.
    // El RX no reproduce un literal 32'hA1B2C3D4: arma 24 bits y extiende signo a 32 en m_axis.
    // Cambiá left_sample/right_sample para probar; cada medio marco LR lleva un canal.
    logic [23:0] left_sample  = 24'h112200; // Valor inicial
    logic [23:0] right_sample = 24'h445500; // Valor inicial
    logic [31:0] shift_reg = 0;
    logic        lrclk_prev = 1'b0;
    int unsigned bit_count = 32; // >31 = idle hasta primer marco

    always_ff @(posedge sclk_out_0)
        lrclk_prev <= lrclk_out_0;

    // Desplazamiento y carga en negedge BCLK (estándar I2S: 1 BCLK tras flanco LR, luego MSB…)
    always_ff @(negedge sclk_out_0) begin
        if (lrclk_out_0 != lrclk_prev) begin
            bit_count <= 0;
            
            // Al iniciar un nuevo marco (LRCLK baja a 0 para el canal Izquierdo), incrementamos los datos
            if (lrclk_out_0 == 1'b0) begin
                left_sample <= left_sample + 1;
                right_sample <= right_sample + 1;
            end
        end else begin
            if (bit_count == 0) begin
                shift_reg <= (lrclk_out_0 == 1'b0) ? {left_sample, 8'b0} : {right_sample, 8'b0};
                bit_count <= 1;
            end else if (bit_count < 32) begin
                shift_reg <= {shift_reg[30:0], 1'b0};
                bit_count <= bit_count + 1;
            end
        end
    end

    wire sdata_bit = (bit_count > 0 && bit_count <= 32) ? shift_reg[31] : 1'b0;

    always_ff @(posedge sclk_out_0)
        sdata_0_in_reg <= sdata_bit;

    assign sdata_0_in_0 = sdata_0_in_reg;

    // Conectamos el generador de reloj al cable que va al puerto inout del Zynq
    assign FIXED_IO_ps_clk = ps_clk_generator;
    assign FIXED_IO_ps_porb = ps_porb_generator;
    assign FIXED_IO_ps_srstb = ps_srstb_generator;

    // =========================================================================
    // Generacion del Reloj Externo
    // =========================================================================
    // Reloj de sistema 50 MHz (periodo 20 ns) — debe coincidir con FCLK/clk_wiz en el BD
    initial sys_clock = 0;
    always #10 sys_clock = ~sys_clock;

    // =========================================================================
    // Generacion de Reloj y Resets del PS (Zynq)
    // =========================================================================
    initial begin
        ps_clk_generator = 0;
        ps_porb_generator = 0;  // Power-On Reset (Activo en bajo)
        ps_srstb_generator = 0; // System Reset (Activo en bajo)
        #1000; // Incrementado a 1000ns para asegurar >16 ciclos del reloj mas lento (AXI VIP)
        ps_porb_generator = 1;  // Liberamos los resets
        ps_srstb_generator = 1;
    end
    // Reloj del PS a ~33.33 MHz (Periodo de 30ns)
    always #15 ps_clk_generator = ~ps_clk_generator;

    initial begin
        $display("=================================================");
        $display("   Iniciando Simulacion con Zynq VIP (SystemVerilog)  ");
        $display("=================================================");

        // 1. Esperar un tiempo para que el sistema salga del Reset inicial
        // Aumentamos la espera a 50 microsegundos (50000 ns). Esto le da tiempo al bloque
        // Processor System Reset y a cualquier MMCM/PLL para hacer "lock" y liberar el bus AXI.
        #500;
        $display("[TB %t] Sistema inicializado. Configurando perifericos...", $time);

        // =========================================================================
        // LIBERAR RESETS DEL FPGA (PL)
        // =========================================================================
        // En una placa real, el FSBL (Bootloader) libera los FCLK_RESET0_N.
        // En simulacion, el Zynq VIP los mantiene en 0 por defecto, lo que bloquea
        // el AXI SmartConnect y los IPs. Debemos liberarlos manualmente:
        dut.design_1_i.processing_system7_0.inst.fpga_soft_reset(32'h0);
        
        #25000; // Esperamos 25us (25000ns) para asegurar que el MMCM haga "Lock" real en simulacion

        // NOTA IMPORTANTE SOBRE LA JERARQUIA:
        // Tienes que navegar a través del wrapper hasta llegar a la instancia del Zynq.
        // Estructura típica: dut.<nombre_del_block_design>_i.processing_system7_0.inst

        // =========================================================================
        // 2. Configurar el IP I2S (Xilinx i2s_receiver / i2s_transmitter)
        // 2. Preparar configuración del IP I2S (Timing y Canales)
        // =========================================================================
        
        // ATENCION: Al usar IPs separados de Xilinx (Receiver y Transmitter), 
        // cada uno tiene una direccion base distinta. Asumimos 0x43C00000 y 0x43C10000.
        
        // PG308 - Offset 0x20: I2S Timing Control (MCLK_DIV=2, BCLK_DIV=2, FS=64)
        // DIAGNOSTICO: Las mediciones (LRCLK ~38.4kHz) indican que el reloj de referencia
        // del IP I2S no es 50MHz, sino ~40MHz (probablemente generado por el Clock Wizard).
        // NUEVO CALCULO PARA 40 MHz:
        // Buscamos la mejor aproximación a 48 kHz desde 40 MHz.
        // Opcion A (anterior): MCLK_DIV=1, BCLK_DIV=1 -> Div total=16 -> LRCLK = 40MHz/16/64 = 39.06 kHz (Error -18%)
        // Opcion B (NUEVA): MCLK_DIV=2, BCLK_DIV=0 -> Div total=12 -> LRCLK = 40MHz/12/64 = 52.08 kHz (Error +8.5%)
        // La opción B es más cercana y tiene más probabilidades de funcionar en la simulación.
        //
        // El valor a escribir es: {FS_RATIO[15:0], BCLK_DIV[7:0], MCLK_DIV[7:0]}
        // FS_RATIO = 64 (0x0040), BCLK_DIV = 0 (0x00), MCLK_DIV = 2 (0x02) -> 32'h00400002
        $display("[TB %t] Configurando divisores I2S para ~52kHz (aprox. 48kHz con reloj de 40MHz).", $time);
        dut.design_1_i.processing_system7_0.inst.write_data(32'h43C00020, 4, 32'h00400002, resp); // RX Timing
        if (resp != 0) $display("[ERROR] Escritura fallida en RX Timing. Resp: %b", resp);
        dut.design_1_i.processing_system7_0.inst.write_data(32'h43C10020, 4, 32'h00400002, resp); // TX Timing
        if (resp != 0) $display("[ERROR] Escritura fallida en TX Timing. Resp: %b", resp);
        #1000;

        // Offset 0x0C: configuración adicional de control (según tu flujo actual)
        dut.design_1_i.processing_system7_0.inst.write_data(32'h43C0000C, 4, 32'h00000001, resp); // RX Ctrl @0x0C
        if (resp != 0) $display("[ERROR] Escritura fallida en RX Ctrl (0x0C). Resp: %b", resp);
        dut.design_1_i.processing_system7_0.inst.write_data(32'h43C1000C, 4, 32'h00000001, resp); // TX Ctrl @0x0C
        if (resp != 0) $display("[ERROR] Escritura fallida en TX Ctrl (0x0C). Resp: %b", resp);
        #1000;

        $display("[TB %t] Modulos Xilinx I2S preparados (0x20, 0x0C).", $time);

        // =========================================================================
        // 2.5. Configurar el AXI GPIO (Control del Looper Mixer)
        // =========================================================================
        // Asumimos que la base del AXI GPIO quedo mapeada en 0x41200000.
        // Si en Vivado ("Address Editor") quedo con otra base, cambiar este valor:
        begin
            automatic bit [31:0] GPIO_BASE_ADDR = 32'h41200000;
            
            $display("[TB %t] Inicializando Looper Mixer en MODO IDLE (00)...", $time);
            // Escribir 0 en el GPIO (Canal 1, Offset 0x00)
            dut.design_1_i.processing_system7_0.inst.write_data(GPIO_BASE_ADDR, 4, 32'h00000000, resp);
            if (resp != 0) $display("[ERROR] Escritura fallida en el AXI GPIO. Resp: %b", resp);
            
            #1000;
            $display("[TB %t] Looper Mixer configurado.", $time);
        end

        // =========================================================================
        // 3. Configurar el AXI DMA en Modo Simple (S2MM y MM2S)
        // =========================================================================
        
        // --- S2MM (Recepción de Audio desde I2S RX a RAM) ---
        // Paso 0: Aplicar Soft Reset al canal S2MM
        dut.design_1_i.processing_system7_0.inst.write_data(32'h40400030, 4, 32'h00000004, resp); 
        #5000;
        // Paso A: Arrancar el canal S2MM (S2MM_DMACR, offset 0x30)
        dut.design_1_i.processing_system7_0.inst.write_data(32'h40400030, 4, 32'h00000001, resp);

        // --- MM2S (Transmisión de Audio desde RAM a I2S TX) ---
        // Pre-cargamos la memoria RAM que el DMA va a utilizar como buffer circular (4KB = 1024 words)
        // para evitar que el VIP de Zynq devuelva 'X' (valores indefinidos) al arrancar MM2S
        // y para probar lectura/escritura en la misma region (0x00100000).
        for (int j = 0; j < 1024; j++) begin
            bit [31:0] dummy_audio;
            bit [23:0] audio_val;
            bit [3:0]  preamble;
            bit [3:0]  control_bits;
            bit parity;
            
            if (j % 2 == 0) begin
                audio_val = 24'h0A0000 + j; // Canal Izquierdo
                preamble = (j == 0) ? 4'b0001 : 4'b0010; 
            end else begin
                audio_val = 24'h0B0000 + j; // Canal Derecho
                preamble = 4'b0010; 
            end
            
            parity = ^({1'b0, 1'b0, 1'b0, audio_val}); 
            control_bits = {parity, 1'b0, 1'b0, 1'b0};
            dummy_audio = { control_bits, audio_val, preamble };
            
            dut.design_1_i.processing_system7_0.inst.write_mem(dummy_audio, 32'h00100000 + (j*4), 4);
        end
        
        // Paso 0: Aplicar Soft Reset al canal MM2S
        dut.design_1_i.processing_system7_0.inst.write_data(32'h40400000, 4, 32'h00000004, resp); 
        #5000;
        // Paso A: Arrancar el canal MM2S (MM2S_DMACR, offset 0x00)
        dut.design_1_i.processing_system7_0.inst.write_data(32'h40400000, 4, 32'h00000001, resp);

        // --- Iniciar Transferencias Continuas ---
        // Usamos hilos en segundo plano (fork) para re-armar el DMA cada vez que termina
        $display("[TB %t] Configurando DMA S2MM (RX) y MM2S (TX) para buffer circular en 0x00100000.", $time);
        
        fork
            // Hilo S2MM (Recepción hacia memoria) continuo
            begin
                automatic bit [31:0] s2mm_status;
                automatic bit [1:0]  s2mm_resp;
                automatic bit [31:0] mem_data;
                automatic int s2mm_pkt_count = 0;
                automatic bit [31:0] s2mm_addr = 32'h00100000; // Base del buffer
                
                forever begin
                    // 1. Escribir direccion de destino (S2MM_DA)
                    dut.design_1_i.processing_system7_0.inst.write_data(32'h40400048, 4, s2mm_addr, s2mm_resp);
                    // 2. Iniciar S2MM (256 bytes)
                    dut.design_1_i.processing_system7_0.inst.write_data(32'h40400058, 4, 32'h00000100, s2mm_resp);
                    
                    do begin
                        #1000;
                        dut.design_1_i.processing_system7_0.inst.read_data(32'h40400034, 4, s2mm_status, s2mm_resp);
                    end while ((s2mm_status[1] == 0) && (s2mm_status[12] == 0)); // Esperar a Idle o Interrupción (IOC)
                    
                    s2mm_pkt_count++;
                    
                    $display("\n======================================================================");
                    $display("[S2MM MONITOR %t] Paquete S2MM #%0d recibido con exito!", $time, s2mm_pkt_count);
                    $display("======================================================================");
                    $display("Verificando los primeros 16 valores (64 bytes) del buffer en RAM (Base: 0x%08h):", s2mm_addr);
                    
                    // Leer las primeras 16 posiciones de memoria recién escritas por el DMA
                    for (int i = 0; i < 16; i++) begin
                        dut.design_1_i.processing_system7_0.inst.read_mem(s2mm_addr + (i * 4), 4, mem_data);
                        $display("  -> RAM[0x%08h] = 0x%08h", s2mm_addr + (i * 4), mem_data);
                    end
                    $display("======================================================================\n");

                    // Limpiar bandera IOC (escribiendo 1 en el bit 12)
                    dut.design_1_i.processing_system7_0.inst.write_data(32'h40400034, 4, 32'h00001000, s2mm_resp);

                    // Avanzar buffer circular de 4KB (0x1000 bytes)
                    s2mm_addr = s2mm_addr + 32'h00000100;
                    if (s2mm_addr >= 32'h00101000) s2mm_addr = 32'h00100000;
                end
            end

            // Hilo MM2S (Transmisión desde memoria) continuo
            begin
                automatic bit [31:0] mm2s_status;
                automatic bit [1:0]  mm2s_resp;
                automatic bit [31:0] mm2s_addr = 32'h00100000; // Leer desde el mismo buffer
                
                forever begin
                    // 1. Escribir direccion de origen (MM2S_SA)
                    dut.design_1_i.processing_system7_0.inst.write_data(32'h40400018, 4, mm2s_addr, mm2s_resp);
                    // 2. Iniciar MM2S (256 bytes)
                    dut.design_1_i.processing_system7_0.inst.write_data(32'h40400028, 4, 32'h00000100, mm2s_resp);
                    
                    do begin
                        #1000;
                        dut.design_1_i.processing_system7_0.inst.read_data(32'h40400004, 4, mm2s_status, mm2s_resp);
                    end while ((mm2s_status[1] == 0) && (mm2s_status[12] == 0)); // Esperar a Idle o Interrupción (IOC)
                    
                    // Limpiar bandera IOC (escribiendo 1 en el bit 12)
                    dut.design_1_i.processing_system7_0.inst.write_data(32'h40400004, 4, 32'h00001000, mm2s_resp);

                    // Avanzar buffer circular (sigue a S2MM)
                    mm2s_addr = mm2s_addr + 32'h00000100;
                    if (mm2s_addr >= 32'h00101000) mm2s_addr = 32'h00100000;
                end
            end
        join_none

        $display("[TB %t] DMA listo y corriendo en background. Esperando muestras...", $time);

        // =========================================================================
        // 4. Encender los módulos I2S (El "Gatillo")
        // =========================================================================
        // Encendemos primero el TX, y por último el RX donde nacen los datos.
        // PG308 - Offset 0x08: I2S Core Control. Bit 0 = I2S_EN
        dut.design_1_i.processing_system7_0.inst.write_data(32'h43C10008, 4, 32'h00000001, resp); // TX Core Enable
        #1000;
        dut.design_1_i.processing_system7_0.inst.write_data(32'h43C00008, 4, 32'h00000001, resp); // RX Core Enable
        #10000;

        $display("[TB %t] Modulos I2S encendidos (Relojes generandose, datos fluyendo).", $time);

        // =========================================================================
        // 4.5. SECUENCIA DE ESTADOS DEL LOOPER (SIMULANDO PEDAL / CÓDIGO C)
        // =========================================================================
        // Nota: Asegurate de que esta sea la dirección base de tu AXI GPIO
        begin
            automatic bit [31:0] GPIO_BASE = 32'h41200000;
            
            // ESTADO 1: IDLE (Ya establecido arriba, dejamos correr audio libre un rato)
            $display("[TB %t] >>> TEST: MODO IDLE (00) - Audio en vivo al parlante. DMA de grabacion no recibe validos.", $time);
            #2000000; // Dejamos pasar 2 milisegundos de simulacion

            // ESTADO 2: RECORD
            $display("[TB %t] >>> TEST: MODO RECORD (01) - Grabando primera capa en RAM.", $time);
            dut.design_1_i.processing_system7_0.inst.write_data(GPIO_BASE, 4, 32'h00000001, resp);
            #2000000;

            // ESTADO 3: PLAY
            $display("[TB %t] >>> TEST: MODO PLAY (10) - Loop reproduciendose y retroalimentandose a la RAM.", $time);
            dut.design_1_i.processing_system7_0.inst.write_data(GPIO_BASE, 4, 32'h00000002, resp);
            #2000000;

            // ESTADO 4: OVERDUB
            $display("[TB %t] >>> TEST: MODO OVERDUB (11) - Mezclando entrada + loop en el parlante y guardando suma en RAM.", $time);
            dut.design_1_i.processing_system7_0.inst.write_data(GPIO_BASE, 4, 32'h00000003, resp);
            #2000000;
        end
        
        // =========================================================================
        // 5. Verificar el estado del DMA y los datos en memoria
        // =========================================================================
        $display("[TB %t] Verificando estado del DMA y memoria RAM...", $time);

        // --- Estado de S2MM (Recepción) ---
        dut.design_1_i.processing_system7_0.inst.read_data(32'h40400034, 4, read_data, resp);
        $display("[TB %t] Registro de estado S2MM_DMASR (Recepción): 0x%08h", $time, read_data);
        if (read_data[12] == 1 && read_data[14] == 0) begin
            $display("[SUCCESS] El DMA completo la transferencia S2MM (Audio -> RAM) sin errores.");
        end else begin
            $display("[FAILURE] S2MM NO completo la transferencia o reporto un error.");
        end

        // --- Estado de MM2S (Transmisión) ---
        dut.design_1_i.processing_system7_0.inst.read_data(32'h40400004, 4, read_data, resp);
        $display("[TB %t] Registro de estado MM2S_DMASR (Transmisión): 0x%08h", $time, read_data);
        if (read_data[12] == 1 && read_data[14] == 0) begin
            $display("[SUCCESS] El DMA completo la transferencia MM2S (RAM -> Audio) sin errores.");
        end else begin
            $display("[FAILURE] MM2S NO completo la transferencia o reporto un error.");
        end
        
        // Leer varias posiciones de RAM para ver ambos canales multiplexados
        for (int i = 0; i < 8; i++) begin
            dut.design_1_i.processing_system7_0.inst.read_mem(
                32'h00100000 + (i * 4), 4, read_data
            );
            $display("[TB %t] RAM addr 0x%08h: 0x%08h", $time, 32'h00100000 + (i*4), read_data);
        end

        $display("[TB %t] Fin de la simulacion.", $time);
        $finish;
    end

endmodule