/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// VHS Platformer
//
// CONTROLS
//   Playground Gamepad:
//     D-Pad left/right = move
//     Up / A / B / X / Y = jump
//     Start / Select = start / restart
//   Fallback (playground ui_in buttons 0-3, 7):
//     0 = left, 1 = right, 2 = jump, 3 or 7 = start / restart

module tt_um_vga_example(
  input  wire [7:0] ui_in,    
  output wire [7:0] uo_out,  
  input  wire [7:0] uio_in, 
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,  
  input  wire       ena,  
  input  wire       clk,  
  input  wire       rst_n   
);

  function [9:0] get_floor;
    input [5:0] c;
    begin
      case (c)
        6'd4,  6'd5,  6'd9,  6'd18, 6'd19, 6'd29, 6'd30,
        6'd38, 6'd39, 6'd47, 6'd48: get_floor = 10'd480; 
        6'd6,  6'd7,  6'd8,  6'd27, 6'd28,
        6'd55, 6'd56, 6'd57: get_floor = 10'd360;
        6'd13, 6'd14, 6'd15, 6'd35, 6'd36, 6'd37,
        6'd43, 6'd44, 6'd49, 6'd50: get_floor = 10'd340;
        6'd16, 6'd17, 6'd45, 6'd46: get_floor = 10'd280;
        6'd20, 6'd21, 6'd22: get_floor = 10'd220;
        6'd58, 6'd59, 6'd60, 6'd61, 6'd62, 6'd63: get_floor = 10'd320; 
        default: get_floor = 10'd400;
      endcase
    end
  endfunction

  function get_spike;
    input [5:0] c;
    begin
      case (c)
        6'd12, 6'd25, 6'd33, 6'd42: get_spike = 1'b1;
        default:                    get_spike = 1'b0;
      endcase
    end
  endfunction

  function [1:0] dim2;
    input [1:0] c;
    input       d;
    begin
      dim2 = (d && (c != 2'b00)) ? (c - 2'b01) : c;
    end
  endfunction

  wire _unused_ok;

  // VGA timing
  reg [9:0] hpos;
  reg [9:0] vpos;
  reg       hsync_reg;
  reg       vsync_reg;
  reg       last_vsync;

  reg [15:0] lfsr;
  reg [9:0]  tracking_y;
  reg [3:0]  line_jit;
  reg [1:0]  r_pipe1, r_pipe2, r_pipe3;
  reg [1:0]  g_pipe1;

  // Game state
  reg [1:0]  game_state;   
  reg [10:0] player_x;
  reg [9:0]  player_y;
  reg signed [5:0] player_vy;  
  reg        grounded;
  reg [10:0] cam_x;
  reg [5:0]  state_timer;  

  reg [10:0] nx;
  reg [10:0] ex;
  reg [9:0]  ny;
  reg [9:0]  fl_a;
  reg [9:0]  fl_b;
  reg [9:0]  fl;
  reg signed [5:0] vt;
  reg signed [5:0] vn;
  reg        grn;
  reg        wall_r;
  reg        wall_l;
  reg        sp_a;
  reg        sp_b;
  reg        hit;

  assign uio_out = 8'b00000000;
  assign uio_oe  = 8'b00000000;

  reg [1:0]  sync_data;
  reg [1:0]  sync_clk;
  reg [1:0]  sync_latch;
  reg        clk_prev;
  reg        latch_prev;
  reg [11:0] pad_shift;
  reg [11:0] pad_data;

  always @(posedge clk) begin
    if (!rst_n) begin
      sync_data  <= 2'b00;
      sync_clk   <= 2'b00;
      sync_latch <= 2'b00;
      clk_prev   <= 1'b0;
      latch_prev <= 1'b0;
      pad_shift  <= 12'hFFF;
      pad_data   <= 12'hFFF;
    end else begin
      sync_data  <= {sync_data[0],  ui_in[6]};
      sync_clk   <= {sync_clk[0],   ui_in[5]};
      sync_latch <= {sync_latch[0], ui_in[4]};
      clk_prev   <= sync_clk[1];
      latch_prev <= sync_latch[1];
      if (sync_latch[1] && !latch_prev)
        pad_data <= pad_shift;                   
      if (sync_clk[1] && !clk_prev)
        pad_shift <= {pad_shift[10:0], sync_data[1]}; 
    end
  end

  wire pad_present = (pad_data != 12'hFFF);

  wire btn_left  = ui_in[0] | (pad_present & pad_data[5]);
  wire btn_right = ui_in[1] | (pad_present & pad_data[4]);
  wire btn_jump  = ui_in[2] | (pad_present & (pad_data[7] | pad_data[3] | pad_data[11] |
                                              pad_data[2] | pad_data[10]));
  wire btn_start = ui_in[3] | ui_in[7] | (pad_present & (pad_data[8] | pad_data[9]));

  assign _unused_ok = &{ena, uio_in, pad_data[6], pad_data[1:0]};

  wire frame_tick = vsync_reg && !last_vsync;

  wire        in_band = (vpos > tracking_y) && (vpos < (tracking_y + 10'd30));
  wire [9:0]  scr_x   = hpos + (in_band ? {6'd0, line_jit} : 10'd0);
  wire [10:0] world_x = {1'b0, scr_x} + cam_x;
  wire [5:0]  col_index = world_x[10:5];

  wire [9:0]  render_floor_y   = get_floor(col_index);
  wire        render_has_spike = get_spike(col_index);

  wire [10:0] px_full   = player_x - cam_x;
  wire [9:0]  px_screen = px_full[9:0];
  wire [9:0]  px_rel    = scr_x - px_screen;
  wire [9:0]  py_rel    = vpos - player_y;
  wire is_player = (game_state != 2'd2) && (px_rel < 10'd16) && (py_rel < 10'd16);

  wire is_ground = (vpos >= render_floor_y);
  wire is_edge   = is_ground && (vpos < (render_floor_y + 10'd3));
  wire [4:0] spike_sum = {1'b0, world_x[3:0]} + {1'b0, vpos[3:0]};
  wire is_spike  = render_has_spike && (vpos >= (render_floor_y - 10'd16)) &&
                   !is_ground && spike_sum[4];
  wire is_door   = ((col_index == 6'd60) || (col_index == 6'd61)) &&
                   (vpos >= (render_floor_y - 10'd48)) && !is_ground;

  wire        in_icon_box = (hpos > 10'd40) && (hpos < 10'd80) && (vpos > 10'd30) && (vpos < 10'd50);
  wire [9:0]  ix     = hpos - 10'd40;
  wire [9:0]  iy     = vpos - 10'd30;
  wire [9:0]  iy_inv = 10'd50 - vpos;
  wire is_play_icon = in_icon_box && (ix < {iy[8:0], 1'b0}) && (ix < {iy_inv[8:0], 1'b0});

  wire [1:0] noise = lfsr[1:0];

  reg [1:0] raw_r;
  reg [1:0] raw_g;
  reg [1:0] raw_b;

  always @(*) begin
    if (game_state == 2'd2) begin        
      raw_r = noise; raw_g = noise; raw_b = noise;
    end else if (is_play_icon) begin
      raw_r = 2'b11; raw_g = 2'b11; raw_b = 2'b11;
    end else if (is_player) begin
      raw_r = 2'b00; raw_g = 2'b11; raw_b = 2'b10;
    end else if (is_spike) begin
      raw_r = 2'b11; raw_g = 2'b00; raw_b = 2'b00;
    end else if (is_door) begin
      raw_r = 2'b11; raw_g = 2'b11; raw_b = 2'b00;
    end else if (is_edge) begin
      raw_r = 2'b10; raw_g = 2'b10; raw_b = 2'b11;
    end else if (is_ground) begin
      raw_r = 2'b01; raw_g = 2'b01; raw_b = 2'b10;
    end else if (in_band) begin               
      raw_r = {1'b0, noise[0]}; raw_g = {1'b0, noise[0]}; raw_b = {1'b0, noise[0]};
    end else if (game_state == 2'd3) begin       
      raw_r = 2'b00; raw_g = 2'b10; raw_b = 2'b01;
    end else begin                            
      raw_r = 2'b00; raw_g = 2'b00; raw_b = 2'b01;
    end
  end

  wire       video_active = (hpos < 10'd640) && (vpos < 10'd480);
  wire [1:0] in_r = video_active ? raw_r : 2'b00;
  wire [1:0] in_g = video_active ? raw_g : 2'b00;
  wire [1:0] in_b = video_active ? raw_b : 2'b00;

  wire       dim     = vpos[1];
  wire [1:0] final_r = dim2(r_pipe3, dim);
  wire [1:0] final_g = dim2(g_pipe1, dim);
  wire [1:0] final_b = dim2(in_b,    dim);

  assign uo_out = {hsync_reg, final_b[0], final_g[0], final_r[0],
                   vsync_reg, final_b[1], final_g[1], final_r[1]};

  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      hpos <= 10'd0;  vpos <= 10'd0;
      hsync_reg <= 1'b0;  vsync_reg <= 1'b0;  last_vsync <= 1'b0;
      lfsr <= 16'hACE1;
      line_jit <= 4'd0;
      tracking_y <= 10'd0;
      r_pipe1 <= 2'b00;  r_pipe2 <= 2'b00;  r_pipe3 <= 2'b00;  g_pipe1 <= 2'b00;

      game_state  <= 2'd0;
      player_x    <= 11'd64;
      player_y    <= 10'd200;
      player_vy   <= 6'sd0;
      grounded    <= 1'b0;
      cam_x       <= 11'd0;
      state_timer <= 6'd0;
    end else begin
      lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

      r_pipe1 <= in_r;
      r_pipe2 <= r_pipe1;
      r_pipe3 <= r_pipe2;
      g_pipe1 <= in_g;

      if (hpos == 10'd799) begin
        hpos <= 10'd0;
        line_jit <= lfsr[3:0]; 
        if (vpos == 10'd524) vpos <= 10'd0;
        else                 vpos <= vpos + 10'd1;
      end else begin
        hpos <= hpos + 10'd1;
      end
      hsync_reg  <= ~((hpos >= 10'd656) && (hpos < 10'd752));
      vsync_reg  <= ~((vpos >= 10'd490) && (vpos < 10'd492));
      last_vsync <= vsync_reg;

      if (frame_tick) begin

        // VHS tracking band scrolls down the screen
        if (tracking_y > 10'd540) tracking_y <= 10'd0;
        else                      tracking_y <= tracking_y + 10'd2;

        if (game_state == 2'd0) begin
          if (btn_start || btn_jump || btn_left || btn_right) game_state <= 2'd1;
        end
        else if (game_state == 2'd1) begin

          nx = player_x;
          ex = player_x + 11'd18;
          wall_r = (get_floor(ex[10:5]) < (player_y + 10'd14));
          ex = player_x - 11'd3;
          wall_l = (get_floor(ex[10:5]) < (player_y + 10'd14));
          if (btn_right && (player_x < 11'd2000) && !wall_r)     nx = player_x + 11'd3;
          else if (btn_left && (player_x > 11'd16) && !wall_l)   nx = player_x - 11'd3;

          ex   = nx + 11'd15;
          fl_a = get_floor(nx[10:5]);
          fl_b = get_floor(ex[10:5]);
          fl   = (fl_a < fl_b) ? fl_a : fl_b;

          vt = player_vy;
          if (grounded && btn_jump) vt = -6'sd14;
          ny = player_y + {{4{vt[5]}}, vt};
          if (!vt[5] && ((ny + 10'd16) >= fl)) begin
            ny  = fl - 10'd16;
            vn  = 6'sd0;
            grn = 1'b1;
          end else begin
            vn  = (vt < 6'sd12) ? (vt + 6'sd1) : vt; 
            grn = 1'b0;
          end

          ex   = nx + 11'd3;
          sp_a = get_spike(ex[10:5]) && ((ny + 10'd16) > (get_floor(ex[10:5]) - 10'd10));
          ex   = nx + 11'd12;
          sp_b = get_spike(ex[10:5]) && ((ny + 10'd16) > (get_floor(ex[10:5]) - 10'd10));
          hit  = sp_a || sp_b;

          player_x  <= nx;
          player_y  <= ny;
          player_vy <= vn;
          grounded  <= grn;

          if (nx < 11'd320)       cam_x <= 11'd0;
          else if (nx > 11'd1728) cam_x <= 11'd1408;
          else                    cam_x <= nx - 11'd320;

          if ((ny > 10'd400) || hit) begin 
            game_state  <= 2'd2;
            state_timer <= 6'd30;
          end else if (nx > 11'd1920) begin 
            game_state  <= 2'd3;
            state_timer <= 6'd30;
          end
        end
        else begin
          if (state_timer != 6'd0) begin
            state_timer <= state_timer - 6'd1;
          end else if (btn_start || btn_jump) begin
            player_x   <= 11'd64;
            player_y   <= 10'd200;
            player_vy  <= 6'sd0;
            grounded   <= 1'b0;
            cam_x      <= 11'd0;
            game_state <= 2'd1;
          end
        end
      end
    end
  end

endmodule