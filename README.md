# Digital Clock — FPGA Implementation

An FPGA-based digital clock implemented in Verilog. The project implements four fully independent operating modes — Clock, Stopwatch, Alarm, and Timer — all displayed on the onboard 4-digit 7-segment display.

---

## Hardware Requirements

| Component | Details |
|---|---|
| **FPGA Board** | Digilent Basys3 (Artix-7 XC7A35T-1CPG236C) |
| **Toolchain** | Xilinx Vivado 2023.x or later |
| **System Clock** | 100 MHz onboard oscillator (pin W5) |
| **Display** | 4-digit 7-segment display (onboard) |
| **Inputs** | 5 push buttons, 7 switches |
| **Outputs** | 4-digit 7-segment display, 7 LEDs |

---

## File Structure

```
DigitalClock/
├── clock_divider.v          # Divides 100 MHz system clock to 1 Hz
├── button_synchronizer.v    # 3-stage flip-flop synchronizer for button inputs
├── digital_clock_top.v      # Top-level module — all four modes and display logic
├── tb_digital_clock_top.v   # Simulation testbench — 24 test cases
└── README.md                # This file
```

> **Note:** A Vivado XDC pin constraints file is required to map signal names to physical board pins before the project can be synthesised and flashed. The Basys3 master XDC is available from the [Digilent Reference Site](https://digilent.com/reference/programmable-logic/basys-3/reference-manual).

---

## How It Works — Architecture Overview

```
100 MHz oscillator
       │
       ▼
 clock_divider          Divides clock by 100,000,000
       │                Produces a 1 Hz tick
       │  clk_1hz
       ▼
 digital_clock_top
       │
       ├── Clock mode      (mode_clock_sw)
       ├── Stopwatch mode  (mode_stopwatch_sw)
       ├── Alarm mode      (mode_alarm_sw)
       └── Timer mode      (mode_timer_sw)
              │
              ▼
       Display multiplexer
              │
              ▼
       4-digit 7-segment display  (~381 Hz refresh)
```

Button inputs pass through a **3-stage flip-flop synchronizer** (`button_synchronizer.v`) before reaching any logic. This prevents metastable voltage levels — caused by asynchronous button presses — from propagating into the synchronous design domain.

---

## Operating Modes

Switch one mode switch ON at a time. If no switch is active, the display is blank.

---

### Mode 1 — Clock

**Switch:** `mode_clock_sw`

Displays the current time as **MM:SS** on the 7-segment display. The current hour is shown in **binary** on 5 LEDs (`clock_hours_led`).

| Control | Action |
|---|---|
| `btn_clock_set_hour` (left button) | Increment hours (+1, wraps 23 → 0) |
| `btn_clock_set_min` (centre button) | Increment minutes (+1, carries into hours at 59) |
| `btn_clock_set_sec` (right button) | Increment seconds (+1, carries into minutes at 59) |
| `sys_reset` | Clear time to 00:00:00 |

**Rollover behaviour:**
```
Seconds : 59 → 0, carries +1 into minutes
Minutes : 59 → 0, carries +1 into hours
Hours   : 23 → 0  (midnight rollover)
```

**Hours LED example — 13:00:00:**
```
LED5  LED4  LED3  LED2  LED1
  0     1     1     0     1   =  13 (binary)
```

---

### Mode 2 — Stopwatch

**Switch:** `mode_stopwatch_sw`

Counts elapsed time upward in **MM:SS** format, starting from 00:00.

| Control | Action |
|---|---|
| `stopwatch_pause_sw` HIGH | Pause — counter holds its value |
| `stopwatch_pause_sw` LOW | Running — counter increments each second |
| `stopwatch_reset` | Clear elapsed time to 00:00 |

**Behaviour:**
- Pausing and resuming preserves the elapsed value — the counter continues from exactly where it stopped
- Rolls over at 59:59 back to 00:00

---

### Mode 3 — Alarm

**Switch:** `mode_alarm_sw`

Allows the user to set a target **HH:MM** alarm time. When the running clock reaches that time, the `alarm_led` output activates.

| Control | Action |
|---|---|
| `btn_alarm_set_hour` (up button) | Increment alarm hours (+1, wraps 23 → 0) |
| `btn_alarm_set_min` (down button) | Increment alarm minutes (+1, carries into hours at 59) |
| `alarm_reset` | Clear alarm time to 00:00 |

**Display:** While this switch is active, the display shows the **alarm set time** (HH:MM) rather than the current clock time.

> **Known Issue:** The alarm LED currently flickers once per second rather than staying solid when triggered. This is caused by an `secs % 2 == 0` condition in the trigger logic and is scheduled for a future fix.

---

### Mode 4 — Timer

**Switch:** `mode_timer_sw`

A countdown timer. The user sets a target **MM:SS** duration, then starts the countdown. When the timer reaches 00:00, the `timer_done_led` output activates.

| Control | Action |
|---|---|
| `timer_run_sw` LOW | **Set mode** — buttons configure the countdown duration |
| `timer_run_sw` HIGH | **Run mode** — timer counts down each second |
| `btn_timer_set_min` | Increment timer minutes (set mode only) |
| `btn_timer_set_sec` | Increment timer seconds (set mode only) |
| `timer_reset` | Clear timer to 00:00 |

**Countdown behaviour:**
```
Each second: timer_secs − 1
At timer_secs = 0: timer_secs → 59, timer_mins − 1  (borrow)
At timer_mins = 0 AND timer_secs = 0: timer_done_led asserts HIGH
```

> **Known Issue:** After `timer_reset`, both registers are 0, so `timer_done_led` asserts immediately before any duration is set. A `timer_started` guard flag is planned for a future fix.

---

## Display — How Multiplexing Works

The 4-digit display is driven by **multiplexing**. Only one digit is physically ON at any moment, but the chip cycles through all four at ~381 Hz — fast enough that the eye perceives them all as simultaneously lit.

```
Digit select cycle (bits [19:18] of a 20-bit refresh counter):

  00 → digit 1 ON  →  show left tens   (e.g. minutes tens)
  01 → digit 2 ON  →  show left ones   (e.g. minutes ones)
  10 → digit 3 ON  →  show right tens  (e.g. seconds tens)
  11 → digit 4 ON  →  show right ones  (e.g. seconds ones)

Each digit is active for ~2.6 ms  (381 Hz refresh rate)
```

All four mode displays show two pairs of digits:

| Mode | Left pair | Right pair |
|---|---|---|
| Clock | Minutes (MM) | Seconds (SS) |
| Stopwatch | Minutes (MM) | Seconds (SS) |
| Alarm | Hours (HH) | Minutes (MM) |
| Timer | Minutes (MM) | Seconds (SS) |

Hours (in Clock mode) are shown on the **5 binary LEDs**, not on the display.

---

## LED Outputs Summary

| Signal | Active When |
|---|---|
| `clock_hours_led[4:0]` | Clock mode is active — binary-encoded current hour |
| `alarm_led` | Clock time matches the set alarm time |
| `timer_done_led` | Timer countdown has reached 00:00 |

---

## Input Summary

| Signal | Type | Function |
|---|---|---|
| `clk` | Clock | 100 MHz system clock (pin W5) |
| `sys_reset` | Switch/Button | Global reset — clears clock registers |
| `mode_clock_sw` | Switch | Activate Clock mode |
| `mode_stopwatch_sw` | Switch | Activate Stopwatch mode |
| `mode_alarm_sw` | Switch | Activate Alarm mode |
| `mode_timer_sw` | Switch | Activate Timer mode |
| `btn_clock_set_hour` | Button (left) | Clock: increment hours |
| `btn_clock_set_min` | Button (centre) | Clock: increment minutes |
| `btn_clock_set_sec` | Button (right) | Clock: increment seconds |
| `btn_alarm_set_hour` | Button (up) | Alarm: increment alarm hours |
| `btn_alarm_set_min` | Button (down) | Alarm: increment alarm minutes |
| `stopwatch_pause_sw` | Switch | Stopwatch: HIGH = pause, LOW = run |
| `stopwatch_reset` | Switch | Stopwatch: clear elapsed time |
| `timer_run_sw` | Switch | Timer: LOW = set, HIGH = run |
| `btn_timer_set_min` | Button | Timer: increment target minutes |
| `btn_timer_set_sec` | Button | Timer: increment target seconds |
| `alarm_reset` | Switch | Alarm: clear alarm time |
| `timer_reset` | Switch | Timer: clear countdown value |

---

## Module Descriptions

### `clock_divider.v`
Divides the 100 MHz system clock down to 1 Hz using a 32-bit counter. Parameterised via `DIVISOR` — change this value to target a different output frequency without modifying the logic.

### `button_synchronizer.v`
Three-stage D flip-flop chain that synchronizes asynchronous button presses to the system clock domain. Prevents metastable voltages (caused by setup/hold violations) from reaching the digital logic.

### `digital_clock_top.v`
Top-level module. Instantiates the clock divider and three button synchronizers, then implements all four operating modes and the multiplexed 7-segment display driver.

### `tb_digital_clock_top.v`
Behavioural simulation testbench. Covers 24 test cases across all modes. Uses `defparam` to speed up the clock divider for simulation and hierarchical references to observe internal DUT signals directly.
