// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_abs_ctrl : unit testbench for meds_s1_abs_ctrl
// =============================================================================

module tb_meds_s1_abs_ctrl;

  logic       clk_i;
  logic       rst_ni;
  logic       cmd_en_i;
  logic [7:0] cmdtype_i;
  logic       postexec_i;
  logic       cmderr_status_i;
  logic       debug_halted_i;
  logic       debug_reg_ready_i;
  logic       aarpostincrement_i;

  logic       abs_en_o;
  logic       debug_reg_en_o;
  logic       busy_o;
  logic       set_cmderr_o;
  logic       inc_regno_o;

  int unsigned checks = 0;
  int unsigned errors = 0;

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
    .busy_o             (busy_o),
    .set_cmderr_o       (set_cmderr_o),
    .inc_regno_o        (inc_regno_o)
  );

  // ---------------------------------------------------------------------------
  // Check helpers
  // ---------------------------------------------------------------------------
  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-28s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

  task automatic step_clk(input int cycles = 1);
    repeat (cycles) @(posedge clk_i);
    #1;
  endtask

  initial begin
    $display("=== tb_meds_s1_abs_ctrl ===");

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
    debug_halted_i = 1'b1;
    cmdtype_i      = 8'h0;
    cmd_en_i       = 1'b1;
    step_clk(1);
    check1("T1: Enter EXEC_REG_E state", (dut.state_q == dut.EXEC_REG_E), 1'b1);
    check1("T1: busy_o asserted", busy_o, 1'b1);

    cmd_en_i = 1'b0;
    debug_reg_ready_i = 1'b1;
    aarpostincrement_i = 1'b1;
    #1;
    check1("T1: inc_regno_o asserted", inc_regno_o, 1'b1);

    step_clk(1);
    check1("T1: Return to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);
    debug_reg_ready_i = 1'b0;

    // Test 2: Invalid command (Program Buffer requested)
    postexec_i = 1'b1;
    cmd_en_i   = 1'b1;
    step_clk(1);
    check1("T2: Trap postexec to ERROR", (dut.state_q == dut.ERROR_WAIT_E), 1'b1);
    check1("T2: set_cmderr_o asserted", set_cmderr_o, 1'b1);

    cmd_en_i = 1'b0;
    cmderr_status_i = 1'b1;
    step_clk(2);
    check1("T2: Stay in ERROR_WAIT_E", (dut.state_q == dut.ERROR_WAIT_E), 1'b1);

    cmderr_status_i = 1'b0;
    step_clk(1);
    check1("T2: Recover to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_abs_ctrl failed");
    end
  end

endmodule