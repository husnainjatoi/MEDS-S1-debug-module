<!-- 
SPDX-License-Identifier: Apache-2.0
Copyright Maktab-e-Digital Systems Lahore
-->

# Debug Module State Machines

## Purpose
This document details the internal state machine architectures for the Debug Module Controller (`dm_controller`). It covers the two primary Finite State Machines (FSMs) that drive the controller's logic: the **Run Control FSM** and the **Abstract Command FSM**. 

These state machines ensure strict compliance with the RISC-V Debug Specification by safely managing hart execution states, handling resets, and orchestrating register accesses without stalling the core pipeline incorrectly.

---

## 1. Run Control FSM

The Run Control FSM manages the execution state of the connected S1-Core. It translates debugger requests (via the `dmcontrol` register) into physical control signals while monitoring the core's status.

![Run Control FSM](design/run_control_fsm.svg)

### State Descriptions

*   **NORMAL:** The core is actively executing instructions or waiting for interrupts. The controller outputs `debug_req_i = 0`. It transitions to HALTING if a halt is requested (`haltreq == 1`), a trigger matches (`trigger_match`), an ebreak is hit (`ebreak_match`), or a step completes (`step_match`).
*   **HALTING:** The controller asserts the halt request to the core (`debug_req_i = 1`). It waits in this state until the core acknowledges the halt (`debug_halted_o == 1`) and the pipeline is fully idle (`x_idle == 1`). This ensures no half-executed operations are observed. Once confirmed, it asserts `core_halted = 1` and moves to HALTED.
*   **HALTED:** The core is safely in Debug Mode. The controller maintains `debug_req_i = 1`. It remains here until the debugger explicitly clears the halt request and asserts a resume request (`resumereq == 1 & haltreq == 0`).
*   **RESUMING:** The controller drops the halt request (`debug_req_i = 0`) to allow the core to exit Debug Mode. It waits for the core to confirm it is running again (`debug_running_o == 1`), asserts `core_resumed = 1`, and returns to NORMAL.
*   **HART RESET:** Entered from any state if a system or hart reset is triggered (`ndmreset | hartreset`). Upon exiting reset, the FSM checks `resethaltreq`. If `resethaltreq == 1`, it forces the core straight into the HALTED state; otherwise, it returns to NORMAL.

---

## 2. Abstract Command FSM

The Abstract Command FSM orchestrates the execution of debug commands written to the `command` register. It controls the `dm_datapath` and manages the `busy` and `cmderr` status flags visible to the debugger.

![Abstract Command FSM](design/abstract_command_fsm.svg)

### State Descriptions

*   **IDLE:** The FSM waits for a new command. The datapath is disabled (`abs_en = 0`, `debug_reg_en = 0`, `debug_mem_en = 0`) and the `busy` bit is `0`. It transitions to DECODE when a new command is triggered (`cmd_en == 1`) and there are no uncleared errors (`cmderr_status == 0`).
*   **DECODE:** The FSM asserts `busy = 1` to lock out further DMI writes to command registers. It evaluates the `cmdtype` and the core's halt status (`debug_halted_o`). 
    *   If it is a valid register access (`cmdtype == 0`) and the core is halted (`debug_halted_o == 1`), it proceeds to EXEC_REG.
    *   If the command type is unsupported (`cmdtype != 0`) or the core is not in the correct state (`debug_halted_o == 0`), it aborts to ERROR WAIT.
*   **EXEC_REG:** The FSM enables the datapath to perform the register access (`debug_reg_en = 1`, `abs_en = 1`) while keeping `busy = 1`. It waits for the datapath to finish (`debug_reg_ready == 1`). Upon completion, it conditionally increments the register number if auto-increment is enabled (`inc_regno = aarpostincrement`) and returns to IDLE.
*   **ERROR WAIT:** Entered when a command fails validation. The FSM drops the `busy` flag (`busy = 0`) but asserts `set_cmderr = 1` to log the failure in the `abstractcs` register. It remains locked in this state until the external debugger explicitly clears the error (`cmderr == 0`), after which it returns to IDLE.

## Architectural Constraints & Notes
* **Command Interlocking:** The `busy` bit serves as a strict hardware interlock. As shown in the Abstract Command FSM, `busy` is asserted immediately in the DECODE state and held through execution. 
* **Safe Debug Entry:** The Run Control FSM explicitly waits for the `x_idle` signal before transitioning to HALTED. This fulfills the MEDS-S1 specification requirement that GDB must never observe a half-executed coprocessor operation during debug entry.