package fx_pkg;
  parameter int NUM_SLOTS = 3;

  typedef struct packed {
    logic        enable;
    logic [31:0] D_16_16;
    logic [31:0] fb_q1_31;
    logic [31:0] wet_q1_31;
    logic [31:0] lpf_G_q1_31;
  } delay_params_t;
  
  typedef struct packed {
    logic [31:0] D_center_16_16;
    logic [31:0] D_depth_16_16;
    logic [31:0] wet_q1_31;
    logic [31:0] lfo_phase_inc_u32;
  } chorus_params_t;



  typedef struct packed {
    delay_params_t delay;    
  }fx_params_t;


endpackage; // fx_pkg
