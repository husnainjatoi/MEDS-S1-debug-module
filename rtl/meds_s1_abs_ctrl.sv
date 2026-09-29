// SPDX-License-Identifier: Apache-2.0
// Copyright Maktab-e-Digital Systems Lahore

module meds_s1_abs_ctrl (
input  logic clk_i,
input  logic rst_ni,

// Command interface
input  logic cmd_en_i,
input  logic [7:0] cmdtype_i,
input  logic postexec_i,
input  logic cmderr_status_i,

// Status from core
input  logic debug_halted_i,
input  logic debug_reg_ready_i,
input  logic aarpostincrement_i,

// Control outputs
output logic abs_en_o,
output logic debug_reg_en_o,
output logic debug_mem_en_o,
output logic busy_o,
output logic set_cmderr_o,
output logic inc_regno_o
);

typedef enum logic [1:0] {
IDLE_E,
EXEC_REG_E,
ERROR_WAIT_E
} abs_state_e;

abs_state_e state_q, next_state_d;

always_ff @(posedge clk_i or negedge rst_ni) begin
if (!rst_ni) begin
state_q <= IDLE_E;
end else begin
state_q <= next_state_d;
end
end

always_comb begin
// Default assignments
next_state_d   = state_q;
abs_en_o       = 1'b0;
debug_reg_en_o = 1'b0;
debug_mem_en_o = 1'b0;
busy_o         = 1'b0;
set_cmderr_o   = 1'b0;
inc_regno_o    = 1'b0;

case (state_q)
  IDLE_E: begin
    if (cmd_en_i & !cmderr_status_i) begin
      // Combinational decode: success path requires cmdtype 0, halted core, and no program buffer execution
      if (cmdtype_i == 8'h0 & debug_halted_i & !postexec_i) begin
        next_state_d = EXEC_REG_E;
      end else begin
        next_state_d = ERROR_WAIT_E;
      end
    end
  end

  EXEC_REG_E: begin
    abs_en_o       = 1'b1;
    debug_reg_en_o = 1'b1;
    busy_o         = 1'b1;

    if (debug_reg_ready_i) begin
      inc_regno_o  = aarpostincrement_i; // Mealy output on completion
      next_state_d = IDLE_E;
    end
  end

  ERROR_WAIT_E: begin
    abs_en_o     = 1'b1;
    set_cmderr_o = 1'b1;
    busy_o       = 1'b0;

    // Wait for the debugger to clear the error status
    if (!cmderr_status_i) begin
      next_state_d = IDLE_E;
    end
  end

  default: begin
    next_state_d = IDLE_E;
  end
endcase

end

endmodule