// SPDX-License-Identifier: Apache-2.0
// Copyright Maktab-e-Digital Systems Lahore

`timescale 1ns / 1ps

module tb_meds_s1_run_ctrl;

logic clk_i;
logic rst_ni;

// Global overrides
logic dmactive_i;
logic ndmreset_i;
logic hartreset_i;

// Debug requests and triggers
logic haltreq_i;
logic resumereq_i;
logic resethaltreq_i;
logic ebreak_match_i;
logic trigger_match_i;
logic step_match_i;

// Core status inputs
logic debug_halted_i;
logic x_idle_i;
logic core_halted_i;
logic debug_running_i;

// Controller outputs
logic debug_req_o;
logic core_resumed_o;

// Clock generation: 100 MHz (10ns period)
initial clk_i = 0;
always #5 clk_i = ~clk_i;

// Instantiate DUT 
meds_s1_run_ctrl dut (
.clk_i           (clk_i),
.rst_ni          (rst_ni),
.dmactive_i      (dmactive_i),
.ndmreset_i      (ndmreset_i),
.hartreset_i     (hartreset_i),
.haltreq_i       (haltreq_i),
.resumereq_i     (resumereq_i),
.resethaltreq_i  (resethaltreq_i),
.ebreak_match_i  (ebreak_match_i),
.trigger_match_i (trigger_match_i),
.step_match_i    (step_match_i),
.debug_halted_i  (debug_halted_i),
.x_idle_i        (x_idle_i),
.core_halted_i   (core_halted_i),
.debug_running_i (debug_running_i),
.debug_req_o     (debug_req_o),
.core_resumed_o  (core_resumed_o)
);

// Helper task to cycle clock
task automatic step_clk(input int cycles = 1);
repeat (cycles) @(posedge clk_i);
#1;
endtask

// Stimulus sequence
initial begin
$display("[TB] Starting meds_s1_run_ctrl testbench...");

// Initialize all signals
rst_ni          = 1'b0;
dmactive_i      = 1'b0;
ndmreset_i      = 1'b0;
hartreset_i     = 1'b0;
haltreq_i       = 1'b0;
resumereq_i     = 1'b0;
resethaltreq_i  = 1'b0;
ebreak_match_i  = 1'b0;
trigger_match_i = 1'b0;
step_match_i    = 1'b0;
debug_halted_i  = 1'b0;
x_idle_i        = 1'b1;
core_halted_i   = 1'b0;
debug_running_i = 1'b1;

// Apply Power-on Reset
step_clk(2);
rst_ni = 1'b1;
step_clk(2);

// Test 1: Activate Debug Module
$display("[TB] Test 1: Activate DM");
dmactive_i = 1'b1;
step_clk(2);
assert (dut.state_q == dut.NORMAL_E)
  else $fatal(1, "Expected NORMAL_E after dmactive assert");

// Test 2: Standard Halt Request with x_idle delay
$display("[TB] Test 2: Halt request with coprocessor busy");
haltreq_i = 1'b1;
step_clk(1);
assert (dut.state_q == dut.HALTING_E && debug_req_o == 1'b1)
  else $fatal(1, "Expected HALTING_E with debug_req_o == 1");

// Core signals halted, but coprocessor is not yet idle (x_idle == 0)
debug_halted_i = 1'b1;
x_idle_i       = 1'b0;
step_clk(2);
assert (dut.state_q == dut.HALTING_E)
  else $fatal(1, "FSM exited HALTING_E before x_idle asserted!");

// Coprocessor finishes work
x_idle_i = 1'b1;
step_clk(1);
assert (dut.state_q == dut.HALTED_E && debug_req_o == 1'b1)
  else $fatal(1, "Expected HALTED_E after x_idle reached");

// Test 3: Resume sequence
$display("[TB] Test 3: Resuming sequence");
haltreq_i   = 1'b0;
resumereq_i = 1'b1;
step_clk(1);
assert (dut.state_q == dut.RESUMING_E && debug_req_o == 1'b0)
  else $fatal(1, "Expected RESUMING_E with debug_req_o == 0");

resumereq_i = 1'b0;
debug_halted_i = 1'b0;
debug_running_i = 1'b0;
step_clk(2);

// Core signals running again -> check Mealy pulse
debug_running_i = 1'b1;
#1;
assert (core_resumed_o == 1'b1)
  else $fatal(1, "core_resumed_o failed to assert on running edge");

step_clk(1);
assert (dut.state_q == dut.NORMAL_E && core_resumed_o == 1'b0)
  else $fatal(1, "Expected transition to NORMAL_E with core_resumed_o deasserted");

// Test 4: Hart Reset with resethaltreq = 1
$display("[TB] Test 4: Hart reset with resethaltreq = 1");
resethaltreq_i = 1'b1;
hartreset_i    = 1'b1;
step_clk(1);
assert (dut.state_q == dut.HART_RESET_E)
  else $fatal(1, "Expected HART_RESET_E on hartreset_i");

hartreset_i = 1'b0;
step_clk(1);
assert (dut.state_q == dut.HALTED_E)
  else $fatal(1, "Expected direct transition from HART_RESET_E to HALTED_E");

// Test 5: dmactive drop forces NORMAL_E
$display("[TB] Test 5: dmactive == 0 deassertion override");
dmactive_i = 1'b0;
step_clk(1);
assert (dut.state_q == dut.NORMAL_E && debug_req_o == 1'b0)
  else $fatal(1, "Expected immediate transition to NORMAL_E when dmactive_i = 0");

$display("[TB] All tests passed successfully!");
$finish;

end

endmodule