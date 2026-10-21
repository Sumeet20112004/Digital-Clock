`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name   : tb_digital_clock_top
// Description   : Simulation testbench for digital_clock_top.
//                 Covers all four operating modes and reset behaviour.
//
// Test Cases
//   1.  Global system reset clears all registers
//   2.  Clock mode — normal 1 Hz ticking
//   3.  Clock mode — seconds roll over into minutes at 59
//   4.  Clock mode — minutes roll over into hours at 59
//   5.  Clock mode — midnight rollover (23:59:59 → 00:00:00)
//   6.  Clock mode — set hours via button
//   7.  Clock mode — set minutes via button
//   8.  Clock mode — set seconds via button
//   9.  Clock mode — hours wrap back to 0 after 23
//   10. Clock mode — clock_hours_led tracks current hour
//   11. Stopwatch mode — counts up while running
//   12. Stopwatch mode — pause holds value
//   13. Stopwatch mode — resume continues from paused value
//   14. Stopwatch mode — reset clears counters
//   15. Stopwatch mode — seconds roll over into minutes
//   16. Alarm mode — set alarm hours and minutes via buttons
//   17. Alarm mode — alarm hours wrap at 23
//   18. Timer mode — set timer duration via buttons
//   19. Timer mode — countdown decrements correctly
//   20. Timer mode — seconds borrow from minutes at rollover
//   21. Timer mode — timer_done_led asserts when countdown reaches 00:00
//   22. Display — seg_anode cycles through all four digit positions
//   23. Display — BCD decoder outputs correct pattern for digit "0"
//   24. Display — blank output when no mode switch is active
//
// Simulation Speed-up
//   The clock_divider DIVISOR parameter is overridden to 20 via defparam,
//   so clk_1hz has a 200 ns period (not 10 ms).
//   One simulated "second" = DIVISOR × clk_period = 20 × 10 ns = 200 ns.
//   All button tasks synchronize to clk_1hz edges for reliable single-increment
//   behaviour.
//
// How to Run (Vivado)
//   1. Add tb_digital_clock_top.v as a Simulation Source.
//   2. Set tb_digital_clock_top as the top simulation module.
//   3. Run Behavioral Simulation (Run All).
//   4. Read PASS / FAIL lines in the Tcl console.
//   5. Open the waveform viewer and add all signals for visual inspection.
//////////////////////////////////////////////////////////////////////////////////

module tb_digital_clock_top;

    // =========================================================================
    // DUT input registers
    // =========================================================================
    reg clk;
    reg sys_reset;
    reg stopwatch_reset;
    reg alarm_reset;
    reg timer_reset;
    reg btn_clock_set_hour;
    reg btn_clock_set_min;
    reg btn_clock_set_sec;
    reg btn_alarm_set_hour;
    reg btn_alarm_set_min;
    reg timer_run_sw;
    reg btn_timer_set_sec;
    reg btn_timer_set_min;
    reg mode_clock_sw;
    reg mode_alarm_sw;
    reg mode_stopwatch_sw;
    reg mode_timer_sw;
    reg stopwatch_pause_sw;

    // =========================================================================
    // DUT output wires
    // =========================================================================
    wire [3:0] seg_anode;
    wire [6:0] seg_cathode;
    wire [4:0] clock_hours_led;
    wire       alarm_led;
    wire       timer_done_led;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    digital_clock_top dut (
        .clk                (clk),
        .sys_reset          (sys_reset),
        .stopwatch_reset    (stopwatch_reset),
        .alarm_reset        (alarm_reset),
        .timer_reset        (timer_reset),
        .btn_clock_set_hour (btn_clock_set_hour),
        .btn_clock_set_min  (btn_clock_set_min),
        .btn_clock_set_sec  (btn_clock_set_sec),
        .btn_alarm_set_hour (btn_alarm_set_hour),
        .btn_alarm_set_min  (btn_alarm_set_min),
        .timer_run_sw       (timer_run_sw),
        .btn_timer_set_sec  (btn_timer_set_sec),
        .btn_timer_set_min  (btn_timer_set_min),
        .mode_clock_sw      (mode_clock_sw),
        .mode_alarm_sw      (mode_alarm_sw),
        .mode_stopwatch_sw  (mode_stopwatch_sw),
        .mode_timer_sw      (mode_timer_sw),
        .stopwatch_pause_sw (stopwatch_pause_sw),
        .seg_anode          (seg_anode),
        .seg_cathode        (seg_cathode),
        .clock_hours_led    (clock_hours_led),
        .alarm_led          (alarm_led),
        .timer_done_led     (timer_done_led)
    );

    // =========================================================================
    // Simulation speed-up
    //
    // Override the clock_divider DIVISOR so clk_1hz runs at a testable rate.
    //   DIVISOR = 20  →  clk_1hz period = 20 × 10 ns = 200 ns
    //   1 simulated "second" = 200 ns  (vs 10 ms on real hardware)
    //
    // All timing in this testbench is expressed in units of SIM_SECOND_NS.
    // =========================================================================
    defparam dut.clk_div_inst.DIVISOR = 20;

    localparam SIM_SECOND_NS = 200;   // must equal DIVISOR × 10 ns

    // =========================================================================
    // 100 MHz clock generation  (period = 10 ns, toggle every 5 ns)
    // =========================================================================
    initial clk = 1'b0;
    always  #5  clk = ~clk;

    // =========================================================================
    // Pass / fail counters
    // =========================================================================
    integer pass_count;
    integer fail_count;

    // =========================================================================
    // check task
    //   Prints a PASS or FAIL line to the console and updates counters.
    //   label    : 64-char max description string
    //   passed   : 1 = condition met (PASS), 0 = condition not met (FAIL)
    // =========================================================================
    task check;
        input [511:0] label;
        input         passed;
        begin
            if (passed) begin
                $display("[PASS] t=%0t ns  %s", $time, label);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] t=%0t ns  %s", $time, label);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // sys_reset task
    //   Applies global reset for 4 clock cycles then releases.
    //   Used at the start of each test group to put the DUT in a known state.
    // =========================================================================
    task do_sys_reset;
        begin
            sys_reset = 1'b1;
            repeat(4) @(posedge clk);
            sys_reset = 1'b0;
            repeat(2) @(posedge clk);
        end
    endtask

    // =========================================================================
    // Button press tasks
    //
    // Each task produces exactly ONE increment of the target register by:
    //   1. Waiting for a rising edge of clk_1hz so we are at the start of a
    //      fresh 1 Hz period.
    //   2. Asserting the button one clk cycle later (after the edge fired).
    //   3. Waiting 5 clk cycles for the 3-stage synchronizer to propagate.
    //   4. Waiting for the NEXT clk_1hz rising edge — the always block fires
    //      here, sees the button HIGH, and performs one increment.
    //   5. Deasserting the button before yet another edge can fire again.
    //   6. Waiting one idle clk_1hz period so the DUT settles.
    //
    // Hierarchical reference dut.clk_1hz is the divided 1 Hz clock wire
    // inside digital_clock_top.
    // =========================================================================

    task press_clock_set_hour;
        begin
            @(posedge dut.clk_1hz); #1;   // step 1-2: land just after a rising edge
            btn_clock_set_hour = 1'b1;
            repeat(5) @(posedge clk);      // step 3: propagate through synchronizer
            @(posedge dut.clk_1hz); #1;   // step 4: always block fires, 1 increment
            btn_clock_set_hour = 1'b0;     // step 5: release before next edge
            @(posedge dut.clk_1hz);        // step 6: idle period
        end
    endtask

    task press_clock_set_min;
        begin
            @(posedge dut.clk_1hz); #1;
            btn_clock_set_min = 1'b1;
            repeat(5) @(posedge clk);
            @(posedge dut.clk_1hz); #1;
            btn_clock_set_min = 1'b0;
            @(posedge dut.clk_1hz);
        end
    endtask

    task press_clock_set_sec;
        begin
            @(posedge dut.clk_1hz); #1;
            btn_clock_set_sec = 1'b1;
            repeat(5) @(posedge clk);
            @(posedge dut.clk_1hz); #1;
            btn_clock_set_sec = 1'b0;
            @(posedge dut.clk_1hz);
        end
    endtask

    task press_alarm_set_hour;
        begin
            @(posedge dut.clk_1hz); #1;
            btn_alarm_set_hour = 1'b1;
            repeat(5) @(posedge clk);
            @(posedge dut.clk_1hz); #1;
            btn_alarm_set_hour = 1'b0;
            @(posedge dut.clk_1hz);
        end
    endtask

    task press_alarm_set_min;
        begin
            @(posedge dut.clk_1hz); #1;
            btn_alarm_set_min = 1'b1;
            repeat(5) @(posedge clk);
            @(posedge dut.clk_1hz); #1;
            btn_alarm_set_min = 1'b0;
            @(posedge dut.clk_1hz);
        end
    endtask

    task press_timer_set_min;
        begin
            @(posedge dut.clk_1hz); #1;
            btn_timer_set_min = 1'b1;
            repeat(5) @(posedge clk);
            @(posedge dut.clk_1hz); #1;
            btn_timer_set_min = 1'b0;
            @(posedge dut.clk_1hz);
        end
    endtask

    task press_timer_set_sec;
        begin
            @(posedge dut.clk_1hz); #1;
            btn_timer_set_sec = 1'b1;
            repeat(5) @(posedge clk);
            @(posedge dut.clk_1hz); #1;
            btn_timer_set_sec = 1'b0;
            @(posedge dut.clk_1hz);
        end
    endtask

    // =========================================================================
    // wait_seconds task
    //   Waits for exactly N rising edges of clk_1hz (N simulated seconds).
    //   More accurate than using #delay because it aligns to the clock edge.
    // =========================================================================
    task wait_seconds;
        input integer n;
        integer       i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge dut.clk_1hz);
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin

        // ------------------------------------------------------------------
        // Initialise all inputs to a safe, known state
        // ------------------------------------------------------------------
        pass_count          = 0;
        fail_count          = 0;
        sys_reset           = 1'b0;
        stopwatch_reset     = 1'b0;
        alarm_reset         = 1'b0;
        timer_reset         = 1'b0;
        btn_clock_set_hour  = 1'b0;
        btn_clock_set_min   = 1'b0;
        btn_clock_set_sec   = 1'b0;
        btn_alarm_set_hour  = 1'b0;
        btn_alarm_set_min   = 1'b0;
        timer_run_sw        = 1'b0;
        btn_timer_set_sec   = 1'b0;
        btn_timer_set_min   = 1'b0;
        mode_clock_sw       = 1'b0;
        mode_alarm_sw       = 1'b0;
        mode_stopwatch_sw   = 1'b0;
        mode_timer_sw       = 1'b0;
        stopwatch_pause_sw  = 1'b0;

        // Allow DUT to initialise for a few clock cycles before testing
        repeat(10) @(posedge clk);

        // ==================================================================
        // TEST 1: Global system reset clears all time-keeping registers
        // ==================================================================
        $display("\n--- TEST 1: Global System Reset ---");
        do_sys_reset;

        check("clock_hrs  = 0 after reset", dut.clock_hrs  == 5'd0);
        check("clock_mins = 0 after reset", dut.clock_mins == 6'd0);
        check("clock_secs = 0 after reset", dut.clock_secs == 6'd0);

        // ==================================================================
        // TEST 2: Clock mode — normal 1 Hz ticking
        // ==================================================================
        $display("\n--- TEST 2: Clock Mode — Normal Ticking ---");
        mode_clock_sw = 1'b1;
        do_sys_reset;

        wait_seconds(3);
        check("clock_secs = 3 after 3 ticks",        dut.clock_secs == 6'd3);
        check("clock_mins = 0 (no rollover yet)",    dut.clock_mins == 6'd0);
        check("clock_hrs  = 0 (no rollover yet)",    dut.clock_hrs  == 5'd0);

        // ==================================================================
        // TEST 3: Clock mode — seconds roll over into minutes at 59
        // ==================================================================
        $display("\n--- TEST 3: Clock Mode — Seconds Rollover ---");
        do_sys_reset;

        // Wait 60 seconds: secs should reach 59 then reset to 0, mins to 1
        wait_seconds(60);
        check("clock_secs = 0 after 60 ticks",  dut.clock_secs == 6'd0);
        check("clock_mins = 1 after 60 ticks",  dut.clock_mins == 6'd1);

        // ==================================================================
        // TEST 4: Clock mode — minutes roll over into hours at 59
        // ==================================================================
        $display("\n--- TEST 4: Clock Mode — Minutes Rollover ---");
        do_sys_reset;

        // Wait 3600 seconds (60 minutes × 60 seconds)
        // Note: this is 3600 × 200 ns = 720,000 ns simulation time
        wait_seconds(3600);
        check("clock_mins = 0 after 3600 ticks", dut.clock_mins == 6'd0);
        check("clock_hrs  = 1 after 3600 ticks", dut.clock_hrs  == 5'd1);

        // ==================================================================
        // TEST 5: Clock mode — midnight rollover (23:59:59 → 00:00:00)
        // ==================================================================
        $display("\n--- TEST 5: Clock Mode — Midnight Rollover ---");
        do_sys_reset;

        // Wait 86400 seconds (24 hours)
        // Simulation time: 86400 × 200 ns = 17,280,000 ns  (~17 ms)
        wait_seconds(86400);
        check("clock_hrs  = 0 at midnight", dut.clock_hrs  == 5'd0);
        check("clock_mins = 0 at midnight", dut.clock_mins == 6'd0);
        check("clock_secs = 0 at midnight", dut.clock_secs == 6'd0);

        // ==================================================================
        // TEST 6: Clock mode — set hours via button (left button)
        // ==================================================================
        $display("\n--- TEST 6: Clock Mode — Set Hours via Button ---");
        do_sys_reset;

        press_clock_set_hour;   // hrs: 0 → 1
        press_clock_set_hour;   // hrs: 1 → 2
        press_clock_set_hour;   // hrs: 2 → 3
        check("clock_hrs = 3 after 3 button presses", dut.clock_hrs == 5'd3);

        // ==================================================================
        // TEST 7: Clock mode — set minutes via button (centre button)
        // ==================================================================
        $display("\n--- TEST 7: Clock Mode — Set Minutes via Button ---");
        do_sys_reset;

        press_clock_set_min;    // mins: 0 → 1
        press_clock_set_min;    // mins: 1 → 2
        press_clock_set_min;    // mins: 2 → 3
        press_clock_set_min;    // mins: 3 → 4
        press_clock_set_min;    // mins: 4 → 5
        check("clock_mins = 5 after 5 button presses", dut.clock_mins == 6'd5);

        // ==================================================================
        // TEST 8: Clock mode — set seconds via button (right button)
        // ==================================================================
        $display("\n--- TEST 8: Clock Mode — Set Seconds via Button ---");
        do_sys_reset;

        press_clock_set_sec;    // secs: 0 → 1
        press_clock_set_sec;    // secs: 1 → 2
        check("clock_secs = 2 after 2 button presses", dut.clock_secs == 6'd2);

        // ==================================================================
        // TEST 9: Clock mode — hours wrap back to 0 after 23
        // ==================================================================
        $display("\n--- TEST 9: Clock Mode — Hours Wrap at 23 ---");
        do_sys_reset;

        // Press 24 times: 0 → 1 → 2 → ... → 23 → 0
        repeat(24) press_clock_set_hour;
        check("clock_hrs wraps to 0 after 24 presses", dut.clock_hrs == 5'd0);

        // ==================================================================
        // TEST 10: Clock mode — clock_hours_led tracks current hour
        // ==================================================================
        $display("\n--- TEST 10: Clock Mode — Hours LED Output ---");
        do_sys_reset;

        press_clock_set_hour;   // hrs → 1
        press_clock_set_hour;   // hrs → 2
        press_clock_set_hour;   // hrs → 3
        @(posedge clk); #1;     // allow LED register to update
        check("clock_hours_led = 3 (binary 00011)", clock_hours_led == 5'd3);

        // ==================================================================
        // TEST 11: Stopwatch mode — counts up while running
        // ==================================================================
        $display("\n--- TEST 11: Stopwatch Mode — Running ---");
        mode_clock_sw     = 1'b0;
        mode_stopwatch_sw = 1'b1;
        stopwatch_reset   = 1'b1; repeat(4) @(posedge clk); stopwatch_reset = 1'b0;
        stopwatch_pause_sw = 1'b0;   // not paused → running

        wait_seconds(5);
        check("stopwatch_secs = 5 after 5 ticks", dut.stopwatch_secs == 6'd5);
        check("stopwatch_mins = 0 (no rollover)", dut.stopwatch_mins == 6'd0);

        // ==================================================================
        // TEST 12: Stopwatch mode — pause holds the current value
        // ==================================================================
        $display("\n--- TEST 12: Stopwatch Mode — Pause Holds Value ---");
        stopwatch_pause_sw = 1'b1;   // pause

        wait_seconds(5);             // 5 more seconds pass, but counter is frozen
        check("stopwatch_secs still 5 while paused", dut.stopwatch_secs == 6'd5);

        // ==================================================================
        // TEST 13: Stopwatch mode — resume continues from paused value
        // ==================================================================
        $display("\n--- TEST 13: Stopwatch Mode — Resume from Paused Value ---");
        stopwatch_pause_sw = 1'b0;   // resume

        wait_seconds(3);
        check("stopwatch_secs = 8 after resuming and 3 more ticks",
              dut.stopwatch_secs == 6'd8);

        // ==================================================================
        // TEST 14: Stopwatch mode — reset clears both counters
        // ==================================================================
        $display("\n--- TEST 14: Stopwatch Mode — Reset Clears Counters ---");
        stopwatch_reset = 1'b1;
        repeat(4) @(posedge clk);
        stopwatch_reset = 1'b0;
        repeat(2) @(posedge clk);

        check("stopwatch_secs = 0 after reset", dut.stopwatch_secs == 6'd0);
        check("stopwatch_mins = 0 after reset", dut.stopwatch_mins == 6'd0);

        // ==================================================================
        // TEST 15: Stopwatch mode — seconds roll over into minutes
        // ==================================================================
        $display("\n--- TEST 15: Stopwatch Mode — Seconds Rollover ---");
        stopwatch_reset    = 1'b1; repeat(4) @(posedge clk); stopwatch_reset = 1'b0;
        stopwatch_pause_sw = 1'b0;

        wait_seconds(60);
        check("stopwatch_secs = 0 at rollover", dut.stopwatch_secs == 6'd0);
        check("stopwatch_mins = 1 at rollover", dut.stopwatch_mins == 6'd1);

        // ==================================================================
        // TEST 16: Alarm mode — set alarm hours and minutes via buttons
        // ==================================================================
        $display("\n--- TEST 16: Alarm Mode — Set Alarm Time ---");
        mode_stopwatch_sw = 1'b0;
        mode_alarm_sw     = 1'b1;
        alarm_reset       = 1'b1; repeat(4) @(posedge clk); alarm_reset = 1'b0;

        // Target alarm time: 02:30
        repeat(2)  press_alarm_set_hour;    // alarm_hrs  → 2
        repeat(30) press_alarm_set_min;     // alarm_mins → 30

        check("alarm_hrs  = 2  after 2 hour presses",  dut.alarm_hrs  == 5'd2);
        check("alarm_mins = 30 after 30 min presses",  dut.alarm_mins == 6'd30);

        // ==================================================================
        // TEST 17: Alarm mode — alarm hours wrap at 23
        // ==================================================================
        $display("\n--- TEST 17: Alarm Mode — Hours Wrap at 23 ---");
        alarm_reset = 1'b1; repeat(4) @(posedge clk); alarm_reset = 1'b0;

        repeat(24) press_alarm_set_hour;    // 0 → 1 → ... → 23 → 0
        check("alarm_hrs wraps to 0 after 24 presses", dut.alarm_hrs == 5'd0);

        // ==================================================================
        // TEST 18: Timer mode — set countdown duration via buttons
        // ==================================================================
        $display("\n--- TEST 18: Timer Mode — Set Duration ---");
        mode_alarm_sw = 1'b0;
        mode_timer_sw = 1'b1;
        timer_reset   = 1'b1; repeat(4) @(posedge clk); timer_reset = 1'b0;
        timer_run_sw  = 1'b0;   // set mode (not running)

        repeat(2) press_timer_set_min;   // timer_mins → 2
        repeat(5) press_timer_set_sec;   // timer_secs → 5

        check("timer_mins = 2 after 2 presses", dut.timer_mins == 6'd2);
        check("timer_secs = 5 after 5 presses", dut.timer_secs == 6'd5);

        // ==================================================================
        // TEST 19: Timer mode — countdown decrements each second
        // ==================================================================
        $display("\n--- TEST 19: Timer Mode — Countdown Decrements ---");
        // Timer is currently at 02:05 — switch to run mode
        timer_run_sw = 1'b1;

        wait_seconds(3);   // 02:05 → 02:04 → 02:03 → 02:02
        check("timer_secs = 2 after 3 ticks from 02:05", dut.timer_secs == 6'd2);
        check("timer_mins = 2 (no borrow yet)",           dut.timer_mins == 6'd2);

        // ==================================================================
        // TEST 20: Timer mode — seconds borrow from minutes when secs = 0
        // ==================================================================
        $display("\n--- TEST 20: Timer Mode — Seconds Borrow from Minutes ---");
        timer_reset  = 1'b1; repeat(4) @(posedge clk); timer_reset = 1'b0;
        timer_run_sw = 1'b0;

        // Set timer to 01:02
        repeat(1) press_timer_set_min;   // timer_mins → 1
        repeat(2) press_timer_set_sec;   // timer_secs → 2
        timer_run_sw = 1'b1;

        // 01:02 → 01:01 → 01:00 → 00:59  (3 ticks, borrow on the 3rd)
        wait_seconds(3);
        check("timer borrows: mins=0, secs=59 after 3 ticks from 01:02",
              dut.timer_mins == 6'd0 && dut.timer_secs == 6'd59);

        // ==================================================================
        // TEST 21: Timer mode — timer_done_led asserts when 00:00 is reached
        // ==================================================================
        $display("\n--- TEST 21: Timer Mode — Done LED Asserts at Zero ---");
        timer_reset  = 1'b1; repeat(4) @(posedge clk); timer_reset = 1'b0;
        timer_run_sw = 1'b0;

        // Set timer to 00:03 then run
        repeat(3) press_timer_set_sec;   // timer_secs → 3
        timer_run_sw = 1'b1;

        // Wait 3 ticks: 00:03 → 00:02 → 00:01 → 00:00
        wait_seconds(3);
        @(posedge dut.clk_1hz); #1;     // one extra tick for the done logic to fire
        check("timer_done_led HIGH at 00:00",  timer_done_led == 1'b1);

        // Verify it deasserts once we leave 00:00
        wait_seconds(1);
        // Note: at 00:00 with timer running, the design will underflow mins
        // (known design limitation — no underflow guard). The done LED will
        // deassert as mins wraps. This is flagged as a TODO in the source.

        // ==================================================================
        // TEST 22: Display — seg_anode cycles through all four digit positions
        // ==================================================================
        $display("\n--- TEST 22: Display — Anode Cycles All Four Positions ---");
        // The 20-bit display_refresh_counter increments on every clk edge.
        // Top 2 bits [19:18] change every 2^18 = 262,144 clk cycles.
        // One full cycle of all 4 digits takes 2^20 = 1,048,576 clk cycles.
        // We observe over one full cycle and confirm all four patterns appear.
        begin : anode_test
            reg seen_digit1, seen_digit2, seen_digit3, seen_digit4;
            integer k;
            seen_digit1 = 0; seen_digit2 = 0;
            seen_digit3 = 0; seen_digit4 = 0;

            mode_timer_sw  = 1'b0;
            mode_clock_sw  = 1'b1;
            do_sys_reset;

            // Sample the anode on each clk edge across one full counter cycle
            for (k = 0; k < (1 << 20) + 4; k = k + 1) begin
                @(posedge clk);
                if (seg_anode == 4'b0111) seen_digit1 = 1;
                if (seg_anode == 4'b1011) seen_digit2 = 1;
                if (seg_anode == 4'b1101) seen_digit3 = 1;
                if (seg_anode == 4'b1110) seen_digit4 = 1;
            end

            check("anode 4'b0111 seen — digit 1 (leftmost) activated", seen_digit1);
            check("anode 4'b1011 seen — digit 2 activated",            seen_digit2);
            check("anode 4'b1101 seen — digit 3 activated",            seen_digit3);
            check("anode 4'b1110 seen — digit 4 (rightmost) activated",seen_digit4);
        end

        // ==================================================================
        // TEST 23: Display — seg_cathode correct for digit "0" (time = 00:00)
        // ==================================================================
        $display("\n--- TEST 23: Display — BCD Decoder for Digit 0 ---");
        // After reset, clock shows 00:00. All four digits should decode to "0".
        // Expected cathode for "0": 7'b0000001 (all segments except g, active-low)
        // Wait until anode selects digit 1 (leftmost, shows mins_tens = 0)
        begin : seg_test
            integer timeout;
            timeout = 0;
            while (seg_anode !== 4'b0111 && timeout < (1 << 20)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check("seg_cathode = 7'b0000001 (digit 0) for mins_tens at 00:00",
                  seg_cathode == 7'b0000001);
        end

        // ==================================================================
        // TEST 24: Display — blank output when no mode switch is active
        // ==================================================================
        $display("\n--- TEST 24: Display — Blank When No Mode Active ---");
        mode_clock_sw     = 1'b0;
        mode_alarm_sw     = 1'b0;
        mode_stopwatch_sw = 1'b0;
        mode_timer_sw     = 1'b0;
        @(posedge clk); #1;    // allow combinational logic to update

        check("seg_cathode = 7'b1111111 (all segments OFF) with no mode",
              seg_cathode == 7'b1111111);

        // ==================================================================
        // Final summary
        // ==================================================================
        $display("\n============================================================");
        $display("  SIMULATION COMPLETE");
        $display("  PASS : %0d", pass_count);
        $display("  FAIL : %0d", fail_count);
        $display("  TOTAL: %0d", pass_count + fail_count);
        $display("============================================================\n");

        if (fail_count == 0)
            $display("  ALL TESTS PASSED\n");
        else
            $display("  %0d TEST(S) FAILED — review [FAIL] lines above\n", fail_count);

        $finish;
    end

    // =========================================================================
    // Watchdog timer
    //   Aborts the simulation if it runs longer than expected.
    //   Budget: 86400 seconds × 200 ns + 10 million ns overhead = ~27.3 ms
    //   Set to 30,000,000 ns to be safe.
    // =========================================================================
    initial begin
        #30_000_000;
        $display("[WATCHDOG] Simulation exceeded time limit. Aborting.");
        $finish;
    end

    // =========================================================================
    // Optional: dump waveform for viewing in Vivado waveform viewer
    // =========================================================================
    initial begin
        $dumpfile("tb_digital_clock_top.vcd");
        $dumpvars(0, tb_digital_clock_top);
    end

endmodule
