`timescale 1ns / 1ps

module meds_s1_run_ctrl(
    input logic clk_i,
    input logic rst_ni,
    
    // Global Overrides
    input logic dmactive_i,
    input logic ndmreset_i,
    input logic hartreset_i,
    
    // Debug requests and triggers
    input logic haltreq_i,
    input logic resumereq_i,
    input logic resethaltreq_i,
    input logic ebreak_match_i,
    input logic trigger_match_i,
    input logic step_match_i,
    
    // Status signals from the Core
    input  logic debug_halted_i,
    input  logic x_idle_i,
    input  logic core_halted_i,
    input  logic debug_running_i,
    
    // Control signals to the Core and DM
    output logic debug_req_o,
    output logic core_resumed_o
);

typedef enum logic [2:0] {
NORMAL_E,
HALTING_E,
HALTED_E,
RESUMING_E,
HART_RESET_E
} run_halt_state_e;

run_halt_state_e state_q, next_state_d;

always_ff @(posedge clk_i or negedge rst_ni) begin
if (!rst_ni) begin
state_q <= NORMAL_E;
end else begin
state_q <= next_state_d;
end
end

always_comb begin
// Default assignments to prevent latches
next_state_d   = state_q;
debug_req_o    = 1'b0;
core_resumed_o = 1'b0;
// Highest priority: Global Debug Module inactive
if (!dmactive_i) begin
  next_state_d = NORMAL_E;
  
// Second priority: Hart Reset
end else if (ndmreset_i | hartreset_i) begin
  next_state_d = HART_RESET_E;
  
// FSM execution
end else begin
  case (state_q)
    NORMAL_E: begin
      if (haltreq_i | ebreak_match_i | trigger_match_i | step_match_i) begin
        next_state_d = HALTING_E;
      end
    end

    HALTING_E: begin
      debug_req_o = 1'b1;
      if ((debug_halted_i & x_idle_i) | core_halted_i) begin
        next_state_d = HALTED_E;
      end
    end

    HALTED_E: begin
      debug_req_o = 1'b1;
      if (resumereq_i & !haltreq_i) begin
        next_state_d = RESUMING_E;
      end
    end

    RESUMING_E: begin
      if (debug_running_i) begin
        core_resumed_o = 1'b1; // Mealy output for the transition
        next_state_d   = NORMAL_E;
      end
    end

    HART_RESET_E: begin
      if (resethaltreq_i) begin
        next_state_d = HALTED_E;
      end else begin
        next_state_d = NORMAL_E;
      end
    end

    default: begin
      next_state_d = NORMAL_E;
    end
  endcase
end

end
endmodule