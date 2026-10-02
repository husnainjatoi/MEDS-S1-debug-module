<!-- 
SPDX-License-Identifier: Apache-2.0
Copyright Maktab-e-Digital Systems Lahore
-->

# Debug Module State Machines & RTL Implementation

## Purpose
This document details the internal state machine architectures and SystemVerilog RTL implementation for the Debug Module Controller. It covers the two primary Finite State Machines (FSMs) that drive the controller's logic: the **Run Control FSM** (`meds_s1_run_ctrl.sv`) and the **Abstract Command FSM** (`meds_s1_abs_ctrl.sv`). 

These state machines ensure strict compliance with the RISC-V Debug Specification by safely managing hart execution states, handling asynchronous resets, and orchestrating register accesses without stalling the core pipeline incorrectly. Furthermore, they strictly adhere to the MEDS-S1 interface conventions and clock domain isolation rules.

---

## 1. Run Control FSM (`meds_s1_run_ctrl.sv`)

The Run Control FSM manages the execution state of the connected S1-Core. It translates debugger requests (via the `dmcontrol` register) into physical control signals while monitoring the core's status. It implements a strict priority hierarchy for global overrides like `dmactive_i` and `ndmreset_i`.

![Run Control FSM](design/run_control_fsm.svg)

### State Descriptions

*   **NORMAL_E:** The core is actively executing instructions or waiting for interrupts. The controller outputs `debug_req_o = 0`. It transitions to `HALTING_E` if a halt is requested (`haltreq_i == 1`), a trigger matches (`trigger_match_i`), an ebreak is hit (`ebreak_match_i`), or a step completes (`step_match_i`).
*   **HALTING_E:** The controller asserts the halt request to the core (`debug_req_o = 1`). It waits in this state until the core acknowledges the halt (`debug_halted_i == 1`) and the pipeline's coprocessor interface is fully idle (`x_idle_i == 1`). Once confirmed, it conditionally pulses `core_halted_o = 1` (as a Mealy output) and moves to `HALTED_E`.
*   **HALTED_E:** The core is safely in Debug Mode. The controller maintains `debug_req_o = 1`. It remains here until the debugger explicitly clears the halt request and asserts a resume request (`resumereq_i == 1 & haltreq_i == 0`).
*   **RESUMING_E:** The controller drops the halt request (`debug_req_o = 0`) to allow the core to exit Debug Mode. It waits for the core to confirm it is running again (`debug_running_i == 1`). Upon confirmation, it pulses `core_resumed_o = 1` and returns to `NORMAL_E`.
*   **HART_RESET_E:** Entered asynchronously from any state if a system or hart reset is triggered (`ndmreset_i | hartreset_i`). Upon exiting reset, the FSM checks `resethaltreq_i`. If `resethaltreq_i == 1`, it forces the FSM straight into the `HALTED_E` state; otherwise, it returns to `NORMAL_E`.

### Global Overrides
*   **`dmactive_i == 0`**: Highest priority override. If the Debug Module is deactivated, the FSM is forced immediately to `NORMAL_E`, overriding any pending halts or resets.

---

## 2. Abstract Command FSM (`meds_s1_abs_ctrl.sv`)

The Abstract Command FSM orchestrates the execution of debug commands written to the `command` register. It has been highly optimized into a 3-state machine that combinationally decodes commands to save execution latency. It controls the datapath and manages the `busy_o` and `cmderr` status flags.

![Abstract Command FSM](design/abstract_command_fsm.svg)

### State Descriptions

*   **IDLE_E:** The FSM waits for a new command. The datapath is disabled (`abs_en_o = 0`, `debug_reg_en_o = 0`, `debug_mem_en_o = 0`) and the `busy_o` bit is `0`. When a new command is triggered (`cmd_en_i == 1`) and there are no uncleared errors (`!cmderr_status_i`), the FSM combinationally decodes the command in the same cycle:
    *   **Success Path:** If it is a valid register access (`cmdtype_i == 8'h0`), the core is halted (`debug_halted_i == 1`), and it does *not* request the unsupported Program Buffer (`postexec_i == 0`), it proceeds directly to `EXEC_REG_E`.
    *   **Failure Path:** If the command type is unsupported, the core is running, or `postexec_i == 1` is requested (since `progbufsize` is 0), it aborts directly to `ERROR_WAIT_E`.
*   **EXEC_REG_E:** The FSM enables the datapath to perform the register access (`debug_reg_en_o = 1`, `abs_en_o = 1`) and asserts `busy_o = 1`. It waits for the datapath to finish (`debug_reg_ready_i == 1`). Upon completion, it asserts the Mealy output `inc_regno_o = aarpostincrement_i` and returns to `IDLE_E`.
*   **ERROR_WAIT_E:** Entered when a command fails validation. The FSM drops the `busy_o` flag but asserts `set_cmderr_o = 1` to log the failure in the `abstractcs` register. It remains locked in this state until the external debugger explicitly clears the error (`cmderr_status_i == 0`), after which it returns to `IDLE_E`.

---

## 3. RTL Implementation Details

Both controllers are implemented in SystemVerilog using a strict, industry-standard two-block FSM pattern to ensure clean synthesis and glitch-free operation.

*   **Two-Block Architecture:** 
    *   A sequential `always_ff` block updates the `state_q` register on the positive edge of `clk_i` or the asynchronous, active-low reset `rst_ni`.
    *   A combinational `always_comb` block computes the `next_state_d` and drives all outputs based on the current state and inputs.
*   **Latch Prevention:** At the top of every `always_comb` block, all outputs (e.g., `debug_req_o`, `busy_o`) and the `next_state_d` variable are assigned default values (typically `1'b0` or `state_q`). This guarantees no inferred latches are created during synthesis.
*   **Mealy Outputs for Single-Cycle Pulses:** Signals like `core_halted_o`, `core_resumed_o`, and `inc_regno_o` are implemented as Mealy outputs. Instead of being tied statically to a state, they are conditionally asserted *inside* the state transition logic (e.g., `if (debug_running_i) core_resumed_o = 1'b1;`). This ensures they pulse high for exactly one clock cycle precisely when the transition occurs.
*   **Safe Debug Entry:** The Run Control FSM explicitly waits for the `x_idle_i` signal before transitioning to `HALTED_E`. This fulfills the MEDS-S1 specification requirement that GDB must never observe a half-executed coprocessor operation during debug entry.