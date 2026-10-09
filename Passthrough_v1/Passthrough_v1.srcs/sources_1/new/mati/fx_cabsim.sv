// =============================================================================
// fx_cabsim.sv - SIMULACION DE GABINETE por convolucion con un IR real.
//
// FIR directo de 1024 taps (21,3 ms a 48 kHz) con el IR de un Celestion G12H
// (Anniversary, 1x12 cerrado, microfono MD421). El IR viene en BRAM y se puede
// reemplazar desde el PS sin resintetizar (REG_CAB_COEF_ADDR / _DATA).
//
// ARITMETICA (pensada para el DSP48E1, multiplicador 25x18):
//   muestra : in_data Q3.29 -> 25 bits Q3.22, redondeo convergente + saturacion
//   coef    : 18 bits Q1.17  (IR normalizado a max|H(f)| = 0 dB -> |h| < 1)
//   producto: 43 bits Q4.39, acumulador de 48 bits (el del DSP48E1)
//   FIR     : (accA+accB) -> Q3.22 (25 bits), redondeo convergente + saturacion
//   nivel   : y * level[31:14] (25x18, Q1.17) -> Q3.29 redondeado, sat32
//   Error total medido (modelo bit-exacto vs float): ver golden.py / README
//
//   Con max|h| = 1 y sum|h| < 64 el acumulador no puede desbordar
//   (2^24 * 2^17 * 64 = 2^47). El IR de G12H tiene sum|h| = 2,3.
//
// ESTRUCTURA: 2 carriles MAC en paralelo, cada uno con 512 taps.
//   carril A: taps   0..511  -> x[n-k]       * hA[k]
//   carril B: taps 512..1023 -> x[n-512-k]   * hB[k]
//   Linea de retardo: BRAM 1024x25 de doble puerto (A lee/escribe, B lee).
//   Coeficientes: 2 BRAM 512x18 (una por carril).
//   ~520 ciclos por muestra (hay 1041 a 50 MHz / 48 kHz). 3 DSP48 en total.
//
// La linea de retardo se sigue escribiendo en bypass, asi que al activar el
// cab ya tiene historia valida (no hay que limpiarla ni arranca con basura).
//
// Una muestra en vuelo, mismo handshake y bypass que el resto de la cadena.
// =============================================================================
module fx_cabsim (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               enable,

  input  logic               in_valid,
  output logic               in_ready,
  input  logic signed [31:0] in_data,

  output logic               out_valid,
  input  logic               out_ready,
  output logic signed [31:0] out_data,

  // Nivel de salida del cab (Q1.31, 0x7FFFFFFF = 1.0)
  input  logic signed [31:0] level_q1_31,

  // Escritura de coeficientes desde el PS (tap 0..1023, Q1.17)
  input  logic               coef_we,
  input  logic [9:0]         coef_addr,
  input  logic [17:0]        coef_data
);
  localparam int HALF = 512;

  // IR por defecto: G12H md421, 1024 x 18 bits, tap 1023 en los bits altos.
  // Generado por cab_ir_gen.py (no editar a mano).
  localparam logic [18*1024-1:0] IR_DEFAULT = {
    384'h000000000000000000000000000000000000000000000000000000000000000000040001000040001000040001000080,
    384'h002000080002000040001000000000ffffffffffffffffffffffbfffeffffbfffeffffbfffffffffffff000000000000,
    384'h0400010000800030000c00030001000030000c0002000040000ffffffffffffffffffffffc000000003fffffffffffff,
    384'hfffffffffffffffffeffff3fff9fffdbfff2fffbbffeafff9bffe3fff7fffdcfff67ffd6fff53ffd2fff4bffd4fff5bf,
    384'hfdbfff87ffe8fffbbfff4fffdffff8fffdffff6fffd7fff5fffdbfff8fffebfffdffffc0000000080004000100005000,
    384'h100003000080000ffff7fffcffff3fffcffff3fffcffff3fffcffff3fffcfffeffff9fffd7fff1fffb3ffe9fff9fffe5,
    384'hfff93ffe4fff8bffe0fff83ffdffff7fffdefff73ffdcfff77ffe1fff9ffff0fffec00050003800180008000250009c0,
    384'h02600084001b0004c000d0002800080001c000700020000a0003c0015000700023000a8002f000d0003b00108004c001,
    384'h580061001a0006c001b0006a00198006000160004f00114003b000c4002700078001800048000b0000ffffbfffcbffe7,
    384'hfff7bffdafff6fffe0fffa3fff0fffdbfffafffeffff9fffd7fff3fffbfffeafff97ffe3fff87ffe2fffabfff3fffe3f,
    384'hffbfffebfff7fffc7ffedfffafffebfffafffeafff9bffe0fff63ffcefff0fffbdffeebffb6ffebfffa6ffe77ff94ffe,
    384'h2bff7effddbff78ffe0fff91ffe87ffb5fff27ffdcfffb7fffc0001c000b0001ffffdfffcbffe6fff67ffcffff2fffcb,
    384'hfff37ffcdfff17ffb8ffea3ff98ffe2fff81ffdefff78ffdf3ff87ffe5fffa9ffeebffc6fff2fffc8ffeffffb3ffea7f,
    384'hfa3ffe87ffa0ffe87ffa2ffe8bffa1ffe8bffa8ffecbffc1fff47ffe1fffbbfff7ffff0000100018000b000400015000,
    384'h58001300040000d0002c000b000380012000600020000b0003b0013c0065001d8007d001e4006d001640043000bc001e,
    384'h00048000d0002c0007ffff7ffedfff6fffc9ffeefffb4ffed7ffbefff33ffdbfffaffffd000400021000b80038001040,
    384'h0460012c00510016400610018c00620017000530012c004b00144005c001a8007800208008c0025800a3002c000bc003,
    384'h0c00c0002d800a600244007a001980054001080031000880018000600022000d40050001bc008c0029000b90033000da,
    384'h0039000ea003b400ed003a400de0034000bf002ac0092001d40052000b4000afffb7ffd9fff33ffc6fff1bffc6fff0bf,
    384'hfbaffeb7ff9dffe2fff79ffd9fff57ffd27ff3fffce7ff38ffcf3ff43ffd2bff52ffd73ff68ffdebff91ffeb7ffd3fff,
    384'hf8002d001700089002c400d3003c4010c0048c013500510014b0051c01360045400e7002b4006f000d00000fff5fffb5,
    384'hffe5fff7affd77ff43ffcafff16ffc1ffeffffbfbff02ffc2fff17ffca7ff3dffd43ff60ffdabff6fffdbfff6effdbbf,
    384'hf6fffdc7ff77ffe07ff8fffe8fffbafff43ffe0fff9fffe5fff77ffd1fff17ffbcffed7ffb3ffed7ffb5ffecbffadffe,
    384'h8fff94ffe17ff7cffdffff8fffeb7ffd5ffffc0022000e800460011c004b00168006f00214009d002c800c50036000e8,
    384'h003cc00f3003a400d5002e00097001d400590010c0034000a4001e0004c000a0000ffffbfffcbffe7fff5bffbaffe5bf,
    384'hf6effd2bff2fffc7fff18ffc53ff12ffc43ff12ffc73ff35ffd67ff80ffe97ffc3fff53ffdcfff97fff500028001e000,
    384'hbc003a000fc00410011400460010c003b000980008fffb7ffddfff5bffdbfffa7fff6ffff3fff7fffa7ffdafff3fffce,
    384'hfff4fffd9fff7fffe2fff87ffdafff4bffc8ffeebffa8ffe4fff79ffd6fff42ffcb3ff1affc37ff01ffbcbfedbffafff,
    384'hea3ffa1bfe6dff96ffe55ff967fe65ff9e7fe94ffac3fec8ffb67fee3ffbabfef4ffc23ff21ffcf7ff58ffdbfff7cffe,
    384'h0fff88ffe43ff95ffe6fffa4ffea7ffacffeabffa4ffe73ff91ffe07ff6effd73ff4dffd03ff39ffcebff43ffd2bff49,
    384'hffd03ff2dffc57ff05ffc23ff1cffd03ff6bffe43ffa6ffebfffb0ffeb3ffa9ffec3ffbdfff2bffdefffdc000a000580,
    384'h01e0006c000ffffe7ffdcffef7ffa1ffe2fff7affdafff59ffd07ff24ffc0bfee5ffb63fed6ffb6ffeeeffc4fff42ffd,
    384'he3ffbb000300060002b800ef004940152005e40198006c001bc006e401a3005dc01420044800e90034000d0003a40110,
    384'h004e4016100614019a006740192005e801550049000f30032800b4002e000ce003ac010b004840125004780111004100,
    384'h0f9003d000f700408011a004d0014f005a4017b00600017c005e001790062401ae007880212008b00224007f001c2006,
    384'h340173005dc01980072001f40083c020f007fc01e30070801ab006ac01bd0076001f50084802260089c021b0080401da,
    384'h006b4018500590015300570017d006a401d4007bc01e6006c4015f0041000af001bc00530016c007c002c800f0004980,
    384'h154005c40175005a00160005c0019c0075c020900884021d0080401d6006b8019400634018c005f0015c004bc00ec002,
    384'h580047000600014000f4008c003a801380056c014b0043800b6001740025000840045001f400b80038c00f10037800b1,
    384'h001e0004a00100004f001b000950032000f300450013200530015900554013e0042000c2002080051000e800430017c0,
    384'h0800027800ba0031800bb002800084001ac0055000dc0006ffedfff3affa33fdd2ff503fcefff397fd2cff6d7fe54ffb,
    384'he3ff8efffc400150002bffddffe7bff78ffe1fffbcfff9fffe5ffe2bfebfff6c7fca6fefb3fbc8ff0f7fd2eff9a3ffa5,
    384'h002a4014f00640015d0031c0004ffcc3fe55ff6c3fd61ff53ffd6bff723fe4cffaa7fedeffc07feefffb07fee9ffd2ff,
    384'hfc70015400b40026fffe2ff9e7fc96feb1ff987fe447f932fe81ffb56ff227fd5aff753fde2ff627fd27ff33bfc7cff1,
    384'ha7fc79ff0bbfbc0fed9bfabbfe747f958fe503f9a3feafffc2dff78fff620006fffefffaabfd1afef57faf2fed93fd35,
    384'hffcbc00690021bff54ff33ff9eafddb3f585fd4abf66dfe093fa3bff247fe9d00170019600b840444011c803a9008f7f,
    384'hfb3ff55ffb8dfe9fffa86feceffb5cfe8a7f7f2fd717f40afcfcff7b9ff6c003be01c300832020200559007bfffb0ff8,
    384'hfbfdb5ff603fda3ffecc01a2004d3fe7afeb5ff63dfc737f0cafd78c00a803e3c1ec00a6e82e070af7422ee052fc070a
  };

  function automatic logic signed [31:0] sat32_c(input logic signed [63:0] v);
    if (v > 64'sh0000_0000_7FFF_FFFF)       sat32_c = 32'sh7FFF_FFFF;
    else if (v < -64'sh0000_0000_8000_0000) sat32_c = 32'sh8000_0000;
    else                                    sat32_c = v[31:0];
  endfunction

  function automatic logic signed [24:0] sat25_c(input logic signed [63:0] v);
    if (v > 64'sd16777215)       sat25_c = 25'sh0FF_FFFF;
    else if (v < -64'sd16777216) sat25_c = 25'sh100_0000;
    else                         sat25_c = v[24:0];
  endfunction

  // Desplazamiento aritmetico a derecha con REDONDEO CONVERGENTE (al par).
  // Sube 1 LSB si lo descartado es > 1/2, o si es exactamente 1/2 y el bit
  // que queda es impar. Sin sesgo de continua, aun cuando los bits
  // descartados valen justo 1/2 (pasa seguido: el codec deja [5:0] = 0).
  // s es siempre constante en las llamadas -> logica fija, sin barrel shifter.
  // (los argumentos son signed: al pasarlos se extienden con signo a 64 bits;
  //  no usar casts tipo 64'(x), que algunas herramientas extienden con ceros)
  function automatic logic signed [63:0] shr_rne(input logic signed [63:0] v, input int s);
    logic half, rest, odd;
    logic signed [63:0] q;
    half = v[s-1];
    rest = |(v & ((64'sd1 <<< (s-1)) - 64'sd1));
    odd  = v[s];
    q    = v >>> s;                 // separado: si en la misma expresion hay un
                                    // operando unsigned, >>> pasa a ser logico
    shr_rne = q + ((half && (rest || odd)) ? 64'sd1 : 64'sd0);
  endfunction

  // ---------------------------------------------------------------------------
  // Memorias
  // ---------------------------------------------------------------------------
  (* ram_style = "block" *) logic signed [24:0] dline  [0:1023];
  (* ram_style = "block" *) logic signed [17:0] coef_a [0:HALF-1];
  (* ram_style = "block" *) logic signed [17:0] coef_b [0:HALF-1];

  initial begin
    for (int i = 0; i < 1024; i++) dline[i] = '0;
    for (int i = 0; i < HALF; i++) begin
      coef_a[i] = IR_DEFAULT[18*i +: 18];
      coef_b[i] = IR_DEFAULT[18*(i+HALF) +: 18];
    end
  end

  // ---------------------------------------------------------------------------
  // Control
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE = 3'd0, S_RUN = 3'd1, S_DRAIN = 3'd2,
    S_SUM  = 3'd3, S_LVL = 3'd4, S_OUT   = 3'd5
  } st_t;
  st_t st;

  logic [9:0] wptr;       // proxima posicion a escribir
  logic [9:0] base;       // posicion de la muestra mas nueva
  logic [8:0] k;          // tap dentro de cada carril

  logic               out_buf_valid;
  logic signed [31:0] out_buf;

  wire core_in_ready = (st == S_IDLE) && !out_buf_valid;
  wire core_in_fire  = enable && in_valid && core_in_ready;
  wire byp_fire      = !enable && in_valid && out_ready;

  // Escritura en la linea de retardo: activo o en bypass
  wire        dl_we    = core_in_fire || byp_fire;
  wire [24:0] dl_wdata = sat25_c(shr_rne(in_data, 7));   // Q3.29 -> Q3.22

  // Direcciones de lectura (st == S_RUN)
  wire [9:0] rd_a = base - {1'b0, k};
  wire [9:0] rd_b = base - {1'b0, k} - 10'd512;
  wire [9:0] dl_addr_a = dl_we ? wptr : rd_a;

  // Puerto A: escritura o lectura (carril A)
  logic signed [24:0] xa_q, xb_q;
  always_ff @(posedge clk) begin
    if (dl_we) dline[dl_addr_a] <= dl_wdata;
    xa_q <= dline[dl_addr_a];
  end
  // Puerto B: solo lectura (carril B)
  always_ff @(posedge clk) xb_q <= dline[rd_b];

  // Coeficientes: puerto de escritura (PS) + puerto de lectura (MAC)
  logic signed [17:0] ha_q, hb_q;
  always_ff @(posedge clk) begin
    if (coef_we && !coef_addr[9]) coef_a[coef_addr[8:0]] <= coef_data;
    ha_q <= coef_a[k];
  end
  always_ff @(posedge clk) begin
    if (coef_we &&  coef_addr[9]) coef_b[coef_addr[8:0]] <= coef_data;
    hb_q <= coef_b[k];
  end

  // ---------------------------------------------------------------------------
  // Pipeline MAC (2 carriles): lectura BRAM -> M (producto) -> P (acumulador)
  // ---------------------------------------------------------------------------
  logic v1, v2, first1, first2;
  logic signed [42:0] m_a, m_b;
  logic signed [47:0] acc_a, acc_b;

  always_ff @(posedge clk) begin
    m_a <= xa_q * ha_q;
    m_b <= xb_q * hb_q;
    if (v2) begin
      acc_a <= first2 ? m_a : acc_a + m_a;
      acc_b <= first2 ? m_b : acc_b + m_b;
    end
  end

  // Salida y nivel
  logic signed [24:0] y_r;            // salida del FIR, Q3.22 (25 bits para el DSP)
  logic signed [17:0] lvl18;
  logic signed [42:0] prod_lvl;
  wire  signed [48:0] acc_sum = acc_a + acc_b;

  always_ff @(posedge clk) begin
    lvl18    <= level_q1_31[31:14];
    prod_lvl <= y_r * lvl18;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= S_IDLE; wptr <= '0; base <= '0; k <= '0;
      v1 <= 1'b0; v2 <= 1'b0; first1 <= 1'b0; first2 <= 1'b0;
      y_r <= '0; out_buf <= '0; out_buf_valid <= 1'b0;
    end else begin
      v2     <= v1;
      first2 <= first1;
      v1     <= 1'b0;
      first1 <= 1'b0;

      if (dl_we) wptr <= wptr + 10'd1;

      if (out_buf_valid && out_ready) out_buf_valid <= 1'b0;

      if (!enable) begin
        // bypass: se descarta cualquier calculo en curso
        st <= S_IDLE;
        out_buf_valid <= 1'b0;
      end else begin
        case (st)
          S_IDLE: if (core_in_fire) begin
            base <= wptr;
            k    <= '0;
            st   <= S_RUN;
          end

          S_RUN: begin
            v1     <= 1'b1;
            first1 <= (k == '0);
            k      <= k + 9'd1;
            if (k == 9'(HALF-1)) st <= S_DRAIN;
          end

          S_DRAIN: if (!v1 && !v2) st <= S_SUM;   // acc_a/acc_b completos

          S_SUM: begin
            y_r <= sat25_c(shr_rne(acc_sum, 17));    // Q4.39 -> Q3.22
            st  <= S_LVL;
          end

          S_LVL: st <= S_OUT;                      // prod_lvl se registra aca

          S_OUT: begin
            out_buf       <= sat32_c(shr_rne(prod_lvl, 10));   // Q4.39 -> Q3.29
            out_buf_valid <= 1'b1;
            st            <= S_IDLE;
          end

          default: st <= S_IDLE;
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Handshake / bypass
  // ---------------------------------------------------------------------------
  assign in_ready  = enable ? core_in_ready : out_ready;
  assign out_valid = enable ? out_buf_valid : in_valid;
  assign out_data  = enable ? out_buf       : in_data;

endmodule
