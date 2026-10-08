// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_sba_ctrl : System Bus Access Controller
//
// FSM to manage System Bus Access (SBA) execution for the Debug Module,
// interacting with the 256-bit AXI4 crossbar backbone via an AXI Upsizer.
// Supported sbaccess sizes are 0 (8-bit), 1 (16-bit), 2 (32-bit), and 3 (64-bit).
// =============================================================================

module meds_s1_sba_ctrl (
  input  logic       clk_i,
  input  logic       rst_ni,

  // DMI Interface
  input  logic       dmi_en_i,
  input  logic       dmi_wr_en_i,
  input  logic       dmi_rd_en_i,
  input  logic [7:0] dmi_addr_i,

  // SBA Configuration & Control (from DMI registers)
  input  logic       sbreadonaddr_q,
  input  logic       sbreadondata_q,
  input  logic       sbautoincrement_q,
  input  logic       clear_errors_i,

  // SBA Status (to DMI registers)
  output logic       sbbusy_o,
  output logic       set_sberror_o,
  output logic       set_sbbusyerror_o,
  output logic       inc_sbaddress_o,

  // AXI4 Handshake Interface
  input  logic       axi_arready_i,
  input  logic       axi_awready_i,
  input  logic       axi_wready_i,
  input  logic       axi_rvalid_i,
  input  logic [1:0] axi_rresp_i,
  input  logic       axi_bvalid_i,
  input  logic [1:0] axi_bresp_i,
  output logic       axi_req_valid_o,
  output logic       axi_is_read_o
);

  localparam logic [7:0] SBCS       = 8'h38;
  localparam logic [7:0] SBADDRESS0 = 8'h39;
  localparam logic [7:0] SBDATA0    = 8'h3C;
  localparam logic [1:0] AXI_OKAY   = 2'b00;

  typedef enum logic [1:0] {
    IDLE_E,
    AXI_ADDR_DATA_E,
    AXI_RESP_E,
    ERROR_HALT_E
  } sba_state_e;

  sba_state_e state_q, next_state_d;
  logic       is_read_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= IDLE_E;
      is_read_q <= 1'b0;
    end else begin
      state_q <= next_state_d;

      if (state_q == IDLE_E) begin
        if (dmi_rd_en_i && dmi_addr_i == SBDATA0 && sbreadondata_q) begin
          is_read_q <= 1'b1;
        end else if (dmi_wr_en_i && dmi_addr_i == SBADDRESS0 && sbreadonaddr_q) begin
          is_read_q <= 1'b1;
        end else if (dmi_wr_en_i && dmi_addr_i == SBDATA0) begin
          is_read_q <= 1'b0;
        end
      end
    end
  end

  assign axi_is_read_o = is_read_q;
 
  always_comb begin
    // Default assignments to prevent latches
    next_state_d      = state_q;
    sbbusy_o          = 1'b0;
    set_sberror_o     = 1'b0;
    set_sbbusyerror_o = 1'b0;
    axi_req_valid_o   = 1'b0;
    inc_sbaddress_o   = 1'b0;

    unique case (state_q)
      IDLE_E: begin
        sbbusy_o = 1'b0;

        if ((dmi_wr_en_i && dmi_addr_i == SBADDRESS0 && sbreadonaddr_q) ||
            (dmi_rd_en_i && dmi_addr_i == SBDATA0 && sbreadondata_q) ||
            (dmi_wr_en_i && dmi_addr_i == SBDATA0)) begin
          next_state_d = AXI_ADDR_DATA_E;
        end
      end

      AXI_ADDR_DATA_E: begin
        sbbusy_o        = 1'b1;
        axi_req_valid_o = 1'b1;

        if (dmi_en_i) begin
          set_sbbusyerror_o = 1'b1;
          next_state_d      = ERROR_HALT_E;
        end else if ((is_read_q && axi_arready_i) || (!is_read_q && axi_awready_i && axi_wready_i)) begin
          next_state_d = AXI_RESP_E;
        end
      end

      AXI_RESP_E: begin
        sbbusy_o = 1'b1;

        if (dmi_en_i) begin
          set_sbbusyerror_o = 1'b1;
          next_state_d      = ERROR_HALT_E;
        end else if ((axi_rvalid_i && axi_rresp_i == AXI_OKAY) ||
                     (axi_bvalid_i && axi_bresp_i == AXI_OKAY)) begin
          inc_sbaddress_o = sbautoincrement_q;
          next_state_d    = IDLE_E;
        end else if ((axi_rvalid_i && axi_rresp_i != AXI_OKAY) ||
                     (axi_bvalid_i && axi_bresp_i != AXI_OKAY)) begin
          set_sberror_o = 1'b1;
          next_state_d  = ERROR_HALT_E;
        end
      end

      ERROR_HALT_E: begin
        sbbusy_o = 1'b0;

        // Wait for the debugger to clear the error flags
        if (dmi_wr_en_i && dmi_addr_i == SBCS && clear_errors_i) begin
          next_state_d = IDLE_E;
        end
      end

      default: begin
        next_state_d = IDLE_E;
      end
    endcase
  end

endmodule