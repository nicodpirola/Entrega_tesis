`timescale 1ns/1ps

package fx_dsp_pkg;
  // satura signed 64b -> signed 32b
  function automatic logic signed [31:0] sat32(input logic signed [63:0] v);
    logic overflow;
    begin
      overflow = |(v[63:32] ^ {32{v[31]}});
      if (!overflow)  sat32 = v[31:0];
      else if (v[63]) sat32 = 32'sh8000_0000;
      else            sat32 = 32'sh7FFF_FFFF;
    end
  endfunction // sat32

  //suma signed 32b con saturacion
  function automatic logic signed [31:0] sat_add32(
    input logic signed [31:0] a,
    input logic signed [31:0] b
  );
    logic signed [31:0] s;
    logic               ov_pos, ov_neg;
    begin
      s = a + b;
      ov_pos = !a[31] && !b[31] && s[31];
      ov_neg = a[31]  && b[31]  && !s[31];
      if (ov_pos) sat_add32 = 32'sh7FFF_FFFF;
      else if (ov_neg) sat_add32 = 32'sh8000_0000;
      else sat_add32 = s;
    end
  endfunction // sat_add32

  //resta signed 32b con saturacion
  function automatic logic signed [31:0] sat_sub32(
    input logic signed [31:0] a,
    input logic signed [31:0] b
  );
    logic signed [31:0] s;
    logic               ov_pos, ov_neg;
    begin
      s = a - b;
      ov_pos = !a[31] && b[31] && s[31];
      ov_neg = a[31]  && !b[31] && !s[31];
      if (ov_pos) sat_sub32 = 32'sh7FFF_FFFF;
      else if (ov_neg) sat_sub32 = 32'sh8000_0000;
      else sat_sub32 = s;
    end
  endfunction // sat_sub32

  //Q3.29 * Q1.31 -> Q3.29. Sumamos 0.5 (<<<30) y despues truncamos (>>> 31)
  function automatic logic signed [31:0] mul_aud_q31(
    input logic signed [31:0] a,
    input logic signed [31:0] c_q1_31
  );
    logic signed [63:0] p;
    begin
      p = $signed (a) * $signed(c_q1_31);
      mul_aud_q31 = sat32((p + (64'sd1<<<30)) >>> 31);
    end
  endfunction // mul_aud_q31

  // Q3.29 * Q1.31 -> Q1.31.
  // El producto tiene 29 + 31 = 60 bits fraccionales.
  // Para dejar 31 bits fraccionales se desplaza 60 - 31 = 29 bits.
  // Se agrega 0.5 LSB del resultado antes del shift para redondear.
  function automatic logic signed [31:0] mul_q29_q31_to_q31(
    input logic signed [31:0] a_q3_29,
    input logic signed [31:0] b_q1_31
  );
    logic signed [63:0] p_q4_60;
    begin
      p_q4_60 = $signed(a_q3_29) * $signed(b_q1_31);
      mul_q29_q31_to_q31 = sat32((p_q4_60 + (64'sd1 <<< 28)) >>> 29);
    end
  endfunction // mul_q29_q31_to_q31

  
  function automatic logic [31:0] abs32(input logic signed [31:0] x);
     if (x == 32'sh8000_0000) abs32 = 32'h7FFF_FFFF;
     else                     abs32 = x[31] ? -x : x;
endfunction

  // soft-clip piecewise lineal en q.29 con dos breakpoints
  function automatic logic signed [31:0] softclip_pw2_q29(
    input logic signed [31:0] x,
    input logic signed [31:0] T1_q29,
    input logic signed [31:0] T2_q29,
    input logic signed [31:0] k1_q31,                 
    input logic signed [31:0] k2_q31
  );
    logic signed [31:0] y, y_mag;
    logic signed [31:0] delta1, delta2;
    logic signed [31:0] Y2_q29;
    logic signed [31:0] a_q29;
    logic               neg;
    begin
      neg = x[31];
      a_q29 = $signed(abs32(x));
      if ($signed(T2_q29) < $signed(T1_q29))begin
        delta1 = 32'sd0;
        delta2 = 32'sd0;
        Y2_q29 = T1_q29;        
      end else begin
        delta1 = sat_sub32(a_q29, T1_q29);
        delta2 = sat_sub32(a_q29, T2_q29);
        Y2_q29 = sat_add32(T1_q29, mul_aud_q31(sat_sub32(T2_q29, T1_q29), k1_q31));
      end

      if      ($signed(a_q29) <= $signed(T1_q29)) begin
        y = x;
      end else if($signed(a_q29) <= $signed(T2_q29))begin
        y_mag = sat_add32(T1_q29, mul_aud_q31(delta1, k1_q31));
        y = neg ? -y_mag : y_mag;
      end else begin
        y_mag = sat_add32(Y2_q29, mul_aud_q31(delta2, k2_q31));
        y = neg ? -y_mag : y_mag;
      end
      softclip_pw2_q29 = y;

    end
  endfunction // softclip_pw2_q29

  
endpackage