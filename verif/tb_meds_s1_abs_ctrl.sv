// SPDX-License-Identifier: Apache-2.0
// Copyright Maktab-e-Digital Systems Lahore

`timescale 1ns / 1ps

module tb_meds_s1_abs_ctrl;

logic clk_i;
logic rst_ni;
logic cmd_en_i;
logic [7:0] cmdtype_i;
logic postexec_i;
logic cmderr_status_i;
logic debug_halted_i;
logic debug_reg_ready_i;
logic aarpostincrement_i;

logic abs_en_o;
logic debug_reg_en_o;
logic debug_mem_en_o;
logic busy_o;
logic set_cmderr_o;
logic inc_regno_o;

initial clk_i = 0;
always #5 clk_i = ~clk_i;

meds_s1_abs_ctrl dut (
.clk_i              (clk_i),
.rst_ni             (rst_ni),
.cmd_en_i           (cmd_en_i),
.cmdtype_i          (cmdtype_i),
.postexec_i         (postexec_i),
.cmderr_status_i    (cmderr_status_i),
.debug_halted_i     (debug_halted_i),
.debug_reg_ready_i  (debug_reg_ready_i),
.aarpostincrement_i (aarpostincrement_i),
.abs_en_o           (abs_en_o),
.debug_reg_en_o     (debug_reg_en_o),
.debug_mem_en_o     (debug_mem_en_o),
.busy_o             (busy_o),
.set_cmderr_o       (set_cmderr_o),
.inc_regno_o        (inc_regno_o)
);

task automatic step_clk(input int cycles = 1);
repeat (cycles) @(posedge clk_i);
#1;
endtask

initial begin
$display("[TB] Starting meds_s1_abs_ctrl testbench...");

rst_ni             = 1'b0;
cmd_en_i           = 1'b0;
cmdtype_i          = 8'h0;
postexec_i         = 1'b0;
cmderr_status_i    = 1'b0;
debug_halted_i     = 1'b0;
debug_reg_ready_i  = 1'b0;
aarpostincrement_i = 1'b0;

step_clk(2);
rst_ni = 1'b1;
step_clk(2);

// Test 1: Valid Register Access
$display("[TB] Test 1: Valid Register Access");
debug_halted_i = 1'b1;
cmdtype_i      = 8'h0;
cmd_en_i       = 1'b1;
step_clk(1);
assert (dut.state_q == dut.EXEC_REG_E && busy_o == 1'b1)
  else $fatal(1, "Failed to enter EXEC_REG_E");

cmd_en_i = 1'b0;
debug_reg_ready_i = 1'b1;
aarpostincrement_i = 1'b1;
#1;
assert (inc_regno_o == 1'b1) else $fatal(1, "inc_regno_o failed to assert");

step_clk(1);
assert (dut.state_q == dut.IDLE_E) else $fatal(1, "Failed to return to IDLE_E");
debug_reg_ready_i = 1'b0;

// Test 2: Invalid command (Program Buffer requested)
$display("[TB] Test 2: Invalid command (postexec = 1)");
postexec_i = 1'b1;
cmd_en_i   = 1'b1;
step_clk(1);
assert (dut.state_q == dut.ERROR_WAIT_E && set_cmderr_o == 1'b1)
  else $fatal(1, "Failed to trap postexec into ERROR_WAIT_E");

cmd_en_i = 1'b0;
cmderr_status_i = 1'b1; // Simulate DM setting the error
step_clk(2);
assert (dut.state_q == dut.ERROR_WAIT_E) else $fatal(1, "Exited ERROR_WAIT_E too early");

cmderr_status_i = 1'b0; // Simulate Debugger clearing the error
step_clk(1);
assert (dut.state_q == dut.IDLE_E) else $fatal(1, "Failed to recover from ERROR_WAIT_E");

$display("[TB] All tests passed successfully!");
$finish;

end
endmodule