`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name   : digital_clock_top
// Description   : Top-level module for an FPGA-based digital clock targeting
//                 the Digilent Basys3 board (Artix-7 XC7A35T). Implements four
//                 operating modes selectable via on-board switches:
//
//                   1. Clock     — displays current time as MM:SS on the
//                                  7-segment display; hours shown in binary
//                                  on 5 LEDs. Time is settable via buttons.
//
//                   2. Stopwatch — counts up in minutes and seconds.
//                                  Controlled by a pause switch and reset.
//
//                   3. Alarm     — user sets a target HH:MM time using buttons.
//                                  alarm_led pulses when the clock reaches
//                                  that time. (Known issue: LED flickers rather
//                                  than staying solid — to be fixed.)
//
//                   4. Timer     — user sets a countdown MM:SS duration.
//                                  Counts down every second when run switch
//                                  is active. timer_done_led asserts at zero.
//
// Display       : 4-digit 7-segment display, multiplexed at ~381 Hz.
//                 All modes show two pairs of digits (tens:ones of each field).
//
// Target Board  : Digilent Basys3 — Artix-7 XC7A35T-1CPG236C
// Toolchain     : Xilinx Vivado 2023.x
// System Clock  : 100 MHz onboard oscillator (XDC pin W5, LVCMOS33)
// Language      : Verilog-2001
//
// Dependencies  : clock_divider.v
//                 button_synchronizer.v
//
// Known Issues  : See inline TODO comments for items pending a future fix pass.
//////////////////////////////////////////////////////////////////////////////////

module digital_clock_top (

    // =========================================================================
    // System signals
    // =========================================================================
    input  wire        clk,                   // 100 MHz system clock (XDC pin W5)
    input  wire        sys_reset,             // global reset, active-high
                                              // clears all time-keeping registers

    // =========================================================================
    // Per-mode reset inputs (mapped to individual switches on the board)
    // =========================================================================
    input  wire        stopwatch_reset,       // clears stopwatch minutes and seconds
    input  wire        alarm_reset,           // clears alarm set-time registers
    input  wire        timer_reset,           // clears timer countdown registers

    // =========================================================================
    // Clock set buttons — used in Clock mode to manually adjust the time
    //   btn_clock_set_hour  : left   button — increment hours   (+1, wraps at 23)
    //   btn_clock_set_min   : centre button — increment minutes (+1, wraps at 59,
    //                                         carries into hours)
    //   btn_clock_set_sec   : right  button — increment seconds (+1, wraps at 59,
    //                                         carries into minutes)
    // =========================================================================
    input  wire        btn_clock_set_hour,    // left button   — set clock hours
    input  wire        btn_clock_set_min,     // centre button — set clock minutes
    input  wire        btn_clock_set_sec,     // right button  — set clock seconds

    // =========================================================================
    // Alarm set buttons — used in Alarm mode to configure the trigger time
    //   btn_alarm_set_hour  : up   button — increment alarm hours
    //   btn_alarm_set_min   : down button — increment alarm minutes
    // =========================================================================
    input  wire        btn_alarm_set_hour,    // up   button — set alarm hours
    input  wire        btn_alarm_set_min,     // down button — set alarm minutes

    // =========================================================================
    // Timer control — used in Timer mode
    //   timer_run_sw        : LOW  = set mode (buttons configure countdown value)
    //                         HIGH = run mode (countdown decrements each second)
    //   btn_timer_set_min   : increments timer minutes while in set mode
    //   btn_timer_set_sec   : increments timer seconds while in set mode
    // =========================================================================
    input  wire        timer_run_sw,          // switch: LOW = set, HIGH = run
    input  wire        btn_timer_set_sec,     // button — increment timer seconds
    input  wire        btn_timer_set_min,     // button — increment timer minutes

    // =========================================================================
    // Mode selection switches (one active at a time)
    // =========================================================================
    input  wire        mode_clock_sw,         // switch — activate Clock mode
    input  wire        mode_alarm_sw,         // switch — activate Alarm mode
    input  wire        mode_stopwatch_sw,     // switch — activate Stopwatch mode
    input  wire        mode_timer_sw,         // switch — activate Timer mode

    // =========================================================================
    // Stopwatch control
    // =========================================================================
    input  wire        stopwatch_pause_sw,    // HIGH = paused, LOW = running

    // =========================================================================
    // 7-segment display outputs
    // =========================================================================
    output reg  [3:0]  seg_anode,             // digit enable, active-low one-hot
                                              // bit 3 = leftmost digit,
                                              // bit 0 = rightmost digit
    output reg  [6:0]  seg_cathode,           // segment drive, active-low
                                              // [6]=g [5]=f [4]=e [3]=d
                                              // [2]=c [1]=b [0]=a

    // =========================================================================
    // LED outputs
    // =========================================================================
    output reg  [4:0]  clock_hours_led,       // clock hours shown in binary
                                              // (5 LEDs, valid in Clock mode)
    output reg         alarm_led,             // pulses when alarm time is reached
    output reg         timer_done_led         // asserts when timer reaches 00:00
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    wire clk_1hz;               // 1 Hz clock derived from 100 MHz system clock

    // Synchronized (metastability-safe) versions of the clock-set buttons
    wire btn_set_hour_sync;     // synchronized btn_clock_set_hour
    wire btn_set_min_sync;      // synchronized btn_clock_set_min
    wire btn_set_sec_sync;      // synchronized btn_clock_set_sec

    // =========================================================================
    // Submodule instantiations
    // =========================================================================

    // Divide 100 MHz system clock to 1 Hz — drives all time-keeping logic
    clock_divider clk_div_inst (
        .clk_in  (clk),
        .clk_out (clk_1hz)
    );

    // Pass each clock-set button through a 3-stage synchronizer chain before
    // use in any synchronous always block (prevents metastability propagation)
    button_synchronizer sync_set_hour_inst (
        .clk     (clk),
        .btn_in  (btn_clock_set_hour),
        .btn_out (btn_set_hour_sync)
    );

    button_synchronizer sync_set_min_inst (
        .clk     (clk),
        .btn_in  (btn_clock_set_min),
        .btn_out (btn_set_min_sync)
    );

    button_synchronizer sync_set_sec_inst (
        .clk     (clk),
        .btn_in  (btn_clock_set_sec),
        .btn_out (btn_set_sec_sync)
    );

    // =========================================================================
    // Clock mode — time-keeping registers
    // =========================================================================

    reg [4:0] clock_hrs;        // current hours   (0–23, 5 bits: max 23 < 2^5=32)
    reg [5:0] clock_mins;       // current minutes (0–59, 6 bits: max 59 < 2^6=64)
    reg [5:0] clock_secs;       // current seconds (0–59, 6 bits)

    // Increment the clock every 1 Hz tick.
    // Buttons allow manual time adjustment and take priority over the normal tick.
    //
    // Priority order (highest first):
    //   1. sys_reset          — clear all registers immediately
    //   2. btn_set_min_sync   — increment minutes (centre button)
    //   3. btn_set_hour_sync  — increment hours   (left button)
    //   4. btn_set_sec_sync   — increment seconds (right button)
    //   5. normal 1 Hz tick   — cascade secs → mins → hrs with rollover
    always @(posedge clk_1hz or posedge sys_reset) begin
        if (sys_reset) begin
            clock_secs <= 6'd0;
            clock_mins <= 6'd0;
            clock_hrs  <= 5'd0;

        end else if (btn_set_min_sync) begin
            // Increment minutes; carry into hours when minutes roll over 59
            if (clock_mins == 6'd59) begin
                clock_mins <= 6'd0;
                clock_hrs  <= clock_hrs + 1'b1;
            end else begin
                clock_mins <= clock_mins + 1'b1;
            end

        end else if (btn_set_hour_sync) begin
            // Increment hours; wrap back to 0 after 23
            if (clock_hrs == 5'd23)
                clock_hrs <= 5'd0;
            else
                clock_hrs <= clock_hrs + 1'b1;

        end else if (btn_set_sec_sync) begin
            // Increment seconds; carry into minutes when seconds roll over 59
            if (clock_secs == 6'd59) begin
                clock_secs <= 6'd0;
                clock_mins <= clock_mins + 1'b1;
            end else begin
                clock_secs <= clock_secs + 1'b1;
            end

        end else begin
            // Normal 1-second tick: cascade rollover secs → mins → hrs
            clock_secs <= clock_secs + 1'b1;
            if (clock_secs == 6'd59) begin
                clock_secs <= 6'd0;
                clock_mins <= clock_mins + 1'b1;
                if (clock_mins == 6'd59) begin
                    clock_mins <= 6'd0;
                    clock_hrs  <= clock_hrs + 1'b1;
                    if (clock_hrs == 5'd23)
                        clock_hrs <= 5'd0;      // midnight rollover
                end
            end
        end
    end

    // Drive the 5 binary LEDs with the current hour value (Clock mode only).
    // Hours are not shown on the 7-segment display (which only shows MM:SS).
    always @(posedge clk or posedge sys_reset) begin
        if (mode_clock_sw) begin
            if (sys_reset)
                clock_hours_led <= 5'b00000;
            else
                clock_hours_led <= clock_hrs;
        end
    end

    // =========================================================================
    // Stopwatch mode — free-running count-up timer in minutes and seconds
    // =========================================================================

    reg [5:0] stopwatch_mins;   // elapsed minutes (0–59)
    reg [5:0] stopwatch_secs;   // elapsed seconds (0–59)

    // Count up on every 1 Hz tick.
    // stopwatch_pause_sw HIGH = paused (registers hold value).
    // stopwatch_pause_sw LOW  = running (registers increment).
    // stopwatch_reset         = clear both registers immediately.
    always @(posedge clk_1hz or posedge stopwatch_reset) begin
        if (stopwatch_reset) begin
            stopwatch_secs <= 6'd0;
            stopwatch_mins <= 6'd0;

        end else if (!stopwatch_pause_sw) begin
            // Running: increment seconds and cascade into minutes at rollover
            stopwatch_secs <= stopwatch_secs + 1'b1;
            if (stopwatch_secs == 6'd59) begin
                stopwatch_secs <= 6'd0;
                stopwatch_mins <= stopwatch_mins + 1'b1;
                if (stopwatch_mins == 6'd59)
                    stopwatch_mins <= 6'd0;     // wrap at 59:59
            end
        end
        // When stopwatch_pause_sw is HIGH, no assignment occurs —
        // registers naturally retain their last values
    end

    // =========================================================================
    // Alarm mode — set a target HH:MM and trigger an LED when reached
    // =========================================================================

    reg [4:0] alarm_hrs;        // alarm target hours   (0–23)
    reg [5:0] alarm_mins;       // alarm target minutes (0–59)

    // Set the alarm time using the up (hour) and down (minute) buttons.
    // alarm_reset clears both registers.
    always @(posedge clk_1hz or posedge alarm_reset) begin
        if (alarm_reset) begin
            alarm_mins <= 6'd0;
            alarm_hrs  <= 5'd0;

        end else if (btn_alarm_set_min) begin
            // Down button: increment alarm minutes, carry into hours at 59
            if (alarm_mins == 6'd59) begin
                alarm_mins <= 6'd0;
                alarm_hrs  <= alarm_hrs + 1'b1;
            end else begin
                alarm_mins <= alarm_mins + 1'b1;
            end

        end else if (btn_alarm_set_hour) begin
            // Up button: increment alarm hours, wrap at 23
            if (alarm_hrs == 5'd23)
                alarm_hrs <= 5'd0;
            else
                alarm_hrs <= alarm_hrs + 1'b1;
        end
    end

    // Assert alarm_led when the current clock time matches the set alarm time.
    // TODO: Known issue — (clock_secs % 2 == 0) causes the LED to flicker ON/OFF
    //       every second instead of staying solid. This condition should be
    //       removed so the LED stays HIGH for the entire matching minute.
    //       Fix pending in next revision.
    always @(posedge clk_1hz) begin
        if (alarm_hrs  == clock_hrs  &&
            alarm_mins == clock_mins &&
            clock_secs % 2 == 6'd0)
            alarm_led = 1'b1;
        else
            alarm_led = 1'b0;
    end

    // =========================================================================
    // Timer mode — user-configured countdown with done indicator
    // =========================================================================

    reg [5:0] timer_mins;       // countdown minutes remaining (0–59)
    reg [5:0] timer_secs;       // countdown seconds remaining (0–59)

    // timer_run_sw selects operating mode:
    //   LOW  (set mode) : btn_timer_set_min / btn_timer_set_sec configure the
    //                     countdown duration
    //   HIGH (run mode) : timer decrements by 1 second on every clk_1hz tick,
    //                     borrowing from minutes when seconds reach 0
    //
    // TODO: Known issue — after timer_reset, both registers are 0, so
    //       timer_done_led asserts immediately before any time is configured.
    //       A "timer_started" flag should gate the done signal in a future fix.
    always @(posedge clk_1hz or posedge timer_reset) begin
        if (timer_reset) begin
            timer_mins <= 6'd0;
            timer_secs <= 6'd0;

        end else if (!timer_run_sw) begin
            // Set mode: configure the countdown duration using buttons
            if (btn_timer_set_min) begin
                if (timer_mins == 6'd59)
                    timer_mins <= 6'd0;         // wrap at 59
                else
                    timer_mins <= timer_mins + 1'b1;

            end else if (btn_timer_set_sec) begin
                // Increment seconds; carry into minutes at rollover
                if (timer_secs == 6'd59) begin
                    timer_secs <= 6'd0;
                    timer_mins <= timer_mins + 1'b1;
                end else begin
                    timer_secs <= timer_secs + 1'b1;
                end
            end

        end else begin
            // Run mode: count down every second
            // When seconds reach 0, borrow 1 minute and reset seconds to 59
            if (timer_secs == 6'd0) begin
                timer_secs <= 6'd59;
                timer_mins <= timer_mins - 1'b1;
            end else begin
                timer_secs <= timer_secs - 1'b1;
            end
        end
    end

    // Assert timer_done_led when both registers reach zero
    always @(posedge clk_1hz) begin
        if (timer_secs == 6'd0 && timer_mins == 6'd0)
            timer_done_led = 1'b1;
        else
            timer_done_led = 1'b0;
    end

    // =========================================================================
    // 7-segment display — multiplexed 4-digit scanning
    // =========================================================================

    // A 20-bit free-running counter drives the display refresh cycle.
    // The top 2 bits [19:18] divide the counter into 4 equal phases, selecting
    // which digit is currently active.
    //
    // Refresh timing at 100 MHz:
    //   Full counter cycle : 2^20 ticks × 10 ns = ~10.5 ms
    //   Per digit          : ~10.5 ms / 4        = ~2.6 ms
    //   Refresh rate       : 1 / 10.5 ms         = ~381 Hz
    //   (above the ~60 Hz flicker fusion threshold — appears solid to the eye)
    reg  [19:0] display_refresh_counter;
    wire [1:0]  digit_select;               // 2-bit digit index: 00=D1, 01=D2, 10=D3, 11=D4

    always @(posedge clk or posedge sys_reset) begin
        if (sys_reset)
            display_refresh_counter <= 20'd0;
        else
            display_refresh_counter <= display_refresh_counter + 1'b1;
    end

    assign digit_select = display_refresh_counter[19:18];

    // -------------------------------------------------------------------------
    // Display content selection — choose what to show based on active mode
    //
    // All modes display two pairs: [left_tens][left_ones] : [right_tens][right_ones]
    //   Clock / Stopwatch / Timer : left = minutes,      right = seconds
    //   Alarm                     : left = alarm hours,  right = alarm minutes
    //
    // BCD value 4'b1010 (10) maps to the blank entry in the segment decoder.
    // -------------------------------------------------------------------------
    reg [3:0] disp_left_tens;       // tens digit of left  pair (digit 1, leftmost)
    reg [3:0] disp_left_ones;       // ones digit of left  pair (digit 2)
    reg [3:0] disp_right_tens;      // tens digit of right pair (digit 3)
    reg [3:0] disp_right_ones;      // ones digit of right pair (digit 4, rightmost)

    always @(*) begin
        if (mode_clock_sw) begin
            // Clock mode: show current MM:SS
            disp_left_tens  = clock_mins / 10;
            disp_left_ones  = clock_mins % 10;
            disp_right_tens = clock_secs / 10;
            disp_right_ones = clock_secs % 10;

        end else if (mode_stopwatch_sw) begin
            // Stopwatch mode: show elapsed MM:SS
            disp_left_tens  = stopwatch_mins / 10;
            disp_left_ones  = stopwatch_mins % 10;
            disp_right_tens = stopwatch_secs / 10;
            disp_right_ones = stopwatch_secs % 10;

        end else if (mode_alarm_sw) begin
            // Alarm mode: show alarm set time as HH:MM
            disp_left_tens  = alarm_hrs  / 10;
            disp_left_ones  = alarm_hrs  % 10;
            disp_right_tens = alarm_mins / 10;
            disp_right_ones = alarm_mins % 10;

        end else if (mode_timer_sw) begin
            // Timer mode: show remaining countdown as MM:SS
            disp_left_tens  = timer_mins / 10;
            disp_left_ones  = timer_mins % 10;
            disp_right_tens = timer_secs / 10;
            disp_right_ones = timer_secs % 10;

        end else begin
            // No mode switch active: blank all four digits
            disp_left_tens  = 4'b1010;
            disp_left_ones  = 4'b1010;
            disp_right_tens = 4'b1010;
            disp_right_ones = 4'b1010;
        end
    end

    // -------------------------------------------------------------------------
    // Digit multiplexer — activate one digit per phase and load its BCD value
    //
    // seg_anode is active-low one-hot:
    //   4'b0111 → digit 1 ON (leftmost)
    //   4'b1011 → digit 2 ON
    //   4'b1101 → digit 3 ON
    //   4'b1110 → digit 4 ON (rightmost)
    // -------------------------------------------------------------------------
    reg [3:0] active_digit_bcd;     // BCD value of the currently active digit

    always @(*) begin
        case (digit_select)
            2'b00: begin
                seg_anode        = 4'b0111;         // digit 1 ON
                active_digit_bcd = disp_left_tens;
            end
            2'b01: begin
                seg_anode        = 4'b1011;         // digit 2 ON
                active_digit_bcd = disp_left_ones;
            end
            2'b10: begin
                seg_anode        = 4'b1101;         // digit 3 ON
                active_digit_bcd = disp_right_tens;
            end
            2'b11: begin
                seg_anode        = 4'b1110;         // digit 4 ON
                active_digit_bcd = disp_right_ones;
            end
            default: begin
                seg_anode        = 4'b1111;         // all digits OFF
                active_digit_bcd = 4'b1010;         // blank
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // BCD to 7-segment decoder
    //
    // Converts a 4-bit BCD value (0–9) to the 7-bit active-low cathode pattern.
    // Segment bit mapping: [6]=g  [5]=f  [4]=e  [3]=d  [2]=c  [1]=b  [0]=a
    //
    //  Segment layout:
    //    aaa
    //   f   b
    //   f   b
    //    ggg
    //   e   c
    //   e   c
    //    ddd
    //
    // Active-low: 0 = segment ON, 1 = segment OFF
    // Value 4'b1010 = blank (all segments OFF, used when no mode is active)
    // -------------------------------------------------------------------------
    always @(*) begin
        case (active_digit_bcd)
            4'b0000: seg_cathode = 7'b0000001; // 0 — segments a,b,c,d,e,f
            4'b0001: seg_cathode = 7'b1001111; // 1 — segments b,c
            4'b0010: seg_cathode = 7'b0010010; // 2 — segments a,b,d,e,g
            4'b0011: seg_cathode = 7'b0000110; // 3 — segments a,b,c,d,g
            4'b0100: seg_cathode = 7'b1001100; // 4 — segments b,c,f,g
            4'b0101: seg_cathode = 7'b0100100; // 5 — segments a,c,d,f,g
            4'b0110: seg_cathode = 7'b0100000; // 6 — segments a,c,d,e,f,g
            4'b0111: seg_cathode = 7'b0001111; // 7 — segments a,b,c
            4'b1000: seg_cathode = 7'b0000000; // 8 — all segments
            4'b1001: seg_cathode = 7'b0000100; // 9 — segments a,b,c,d,f,g
            4'b1010: seg_cathode = 7'b1111111; // blank — all segments OFF
            default: seg_cathode = 7'b1111111; // blank for any undefined input
        endcase
    end

endmodule
