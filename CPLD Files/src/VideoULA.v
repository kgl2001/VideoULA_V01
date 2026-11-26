`timescale 1ns / 1ps
/************************************************************************
VideoULA.v
VideoULA V01   - A replacement Video ULA for the BBC Micro
Build 38       - November 2026 - Back-port of the V02/V03 improvements, plus a new
                 experimental CLK_AUTO option.
                 Palette write timing ported from V02/V03 Build 6:
                 three-cycle write (capture / prepare / write) so the SRAM
                 address is stable for one full cycle before nWE falls.
                 Registered data-bus enable. Selectable early/late timing.
                 Cursor alignment ported from V02/V03 Builds 4 and 5:
                 modes 0-6 cursor uses cursor_invert0 (no delay); mode 7
                 cursor uses cursor_invert[0] (one stage, 62.5ns).
                 In 16MHz mode CLK_6M is now generated from CLK_IN (edge
                 pattern based on radiofan's approach, retimed so tD is
                 about 31ns), as in V02/V03 Build 6. The 6MHz edge terms come
                 directly from clk_counter[2:0], so the 6MHz stays locked to
                 the 1MHz after every power-up.
                 CLK_AUTO (experimental, tested on Rev01 hardware only; Rev02-
                 Rev04 not built): one build for both clocks. The mode is read
                 at power-up from the SRAM_nWE pin (JP2: pulled up = 48MHz,
                 pulled down = 16MHz), after which the pin becomes the normal
                 SRAM_nWE output. JP1 and JP2 must both be set to the same mode
                 (1/2 = 48MHz, 2/3 = 16MHz). Rev01 boards have no strap jumper
                 (fixed pull-up): use CLK_48MHZ or CLK_16MHZ, or CLK_AUTO with
                 or without CLK_AUTO_INVERT_STRAP.
Build 37       - August 2026 - Pre-load sram_addr_reg one cycle early
                 (reduces address/nWE skew; setup not guaranteed)
                 Based on community code by hoglet (Stardot forums)
                 Posedge sampling at x111 per DRAM timing analysis
(C) Ken Lowe July 2026.
Community contributions: hoglet (Stardot forums) - unified clock architecture
------------------------------------------------------------------------
CLOCK CONFIGURATION - uncomment ONE define only
NOTE: CLK_6M is always present as a port in both builds.
  48MHz build: CLK_6M drives the SAA5050 6MHz clock from the 48MHz oscillator
  16MHz build: CLK_6M drives the SAA5050 6MHz clock, generated from CLK_IN
               (the motherboard 16MHz), using both clock edges
The NET "CLK_6M" LOC = "P42" constraint in the .ucf can remain
active for both builds.
------------------------------------------------------------------------
Clock architecture (unified):
  A 4-bit clk_counter divides the effective 16MHz clock.
  In 16MHz mode, mhz16_clken=1 so clk_counter increments every CLK_IN tick.
  In 48MHz mode, a 2-bit prescaler divides 48MHz by 3, giving mhz16_clken
  every 3rd tick. clk_counter then behaves identically in both modes.

  CLK_8M   = clk_counter[0]  (8MHz, direct bit tap)
  CLK_4M   = clk_counter[1]  (4MHz, direct bit tap)
  CLK_2M   = clk_counter[2]  (2MHz, direct bit tap)
  CLK_1M   = clk_counter[3]  (1MHz, direct bit tap)
  CLK_CRTC = clk_counter[2] or clk_counter[3] per r0_crtc_2mhz

  CLK_6M:
    48MHz mode: derived from {clk_counter, clk_prescaler} state decode.
      Phase locked to CLK_1M: CLK_6M rises 20.83ns before CLK_1M falls.
      tD = 20.83ns, within SAA5050 requirement of 6-60ns. ✓
    16MHz mode: rising-edge toggle XOR falling-edge toggle on CLK_IN,
      tD about 31ns ✓ (edge spacing has fixed jitter of about 10ns)

  pixel_reg sampled on posedge at end of DRAM access cycle x111:
    DRAM nCAS asserted at x110 (via IC45 74S139, ~12ns delay)
    DRAM data valid after ~67ns (55ns HM4816A-3 access + 12ns IC45)
    67ns < 125ns (2 x 62.5ns cycles) so data valid by end of x111 ✓
    All logic on posedge - no mixed-edge clocking, no BUFG warnings.

Palette storage: external SRAM (IS62C256AL-45TLI)
  SRAM_ADDR[3:0] <- palette index (logical colour)
  SRAM_DATA[3:0] <-> palette data (physical colour)
  SRAM_nWE       <- write enable (active low)
  Note: A palette write takes three 16MHz cycles: capture D[7:4], prepare
        (address driven, nWE high), write (nWE low, D[3:0] driven).
        The address is stable for one full cycle (62.5ns) before nWE falls.
        Write pulse = one 16MHz cycle = 62.5ns, longer than the SRAM tWP min.
************************************************************************/

// ------------------------------------------------------------------------
// CLOCK CONFIGURATION
// ------------------------------------------------------------------------
// Configurations (set exactly one of the first three; the invert define is
// an add-on to CLK_AUTO). Macrocell counts are from the ISE fitter (XC9572XL):
//   CLK_48MHZ  fixed 48MHz build           Rev01-Rev04   tested  (50/72 mc)
//   CLK_16MHZ  fixed 16MHz build           Rev01-Rev04   tested  (53/72 mc)
//   CLK_AUTO   mode from the SRAM_nWE strap at power-up
//              Rev02-Rev04 (JP2), or Rev01 (fixed pull-up = 48MHz)
//              Experimental. Tested on Rev01 hardware only, in both
//              polarities. 70-72/72 mc depending on fitter settings, so
//              there is no headroom. The strap is read at power-up and may
//              occasionally pick the wrong mode; power-cycle to recover.
//   CLK_AUTO + CLK_AUTO_INVERT_STRAP: as CLK_AUTO, pull-up = 16MHz.
// The fixed builds are smaller and have had more testing.
// ------------------------------------------------------------------------
`define CLK_48MHZ
//`define CLK_16MHZ
// CLK_AUTO: mode is read from the SRAM_nWE strap at power-up. To use it,
// comment out CLK_48MHZ above and uncomment this line.
//`define CLK_AUTO
// CLK_AUTO_INVERT_STRAP (used together with CLK_AUTO): inverts the strap
// polarity, so that a pulled-up SRAM_nWE selects 16MHz instead of 48MHz.
// Rev01 boards have a fixed pull-up on SRAM_nWE and no strap jumper, so on
// Rev01 this define chooses the mode at build time:
//   CLK_AUTO                          -> 48MHz (pull-up = 48MHz)
//   CLK_AUTO + CLK_AUTO_INVERT_STRAP  -> 16MHz (pull-up = 16MHz)
// On Rev02-Rev04 leave it undefined: JP2 selects the mode (up = 48MHz,
// down = 16MHz). JP1 (the clock source) must always match the mode.
//`define CLK_AUTO_INVERT_STRAP

`ifdef CLK_48MHZ
  `ifdef CLK_16MHZ
    ERROR_BOTH_CLOCK_DEFINES_SET // deliberate syntax error if both defined
  `endif
`endif
`ifdef CLK_AUTO_INVERT_STRAP
  `ifndef CLK_AUTO
    ERROR_INVERT_STRAP_NEEDS_CLK_AUTO // deliberate syntax error
  `endif
`endif
`ifdef CLK_AUTO
  `ifdef CLK_48MHZ
    ERROR_CLK_AUTO_WITH_FIXED_CLOCK // deliberate syntax error
  `endif
  `ifdef CLK_16MHZ
    ERROR_CLK_AUTO_WITH_FIXED_CLOCK // deliberate syntax error
  `endif
`endif

// ------------------------------------------------------------------------
// SRAM PALETTE WRITE TIMING - select at build time
// ------------------------------------------------------------------------
// A palette write takes three cycles of the 8-cycle clk_counter: capture the
// address from D[7:4], prepare (address driven, nWE high), then write (nWE low,
// data driven). The ULA control register write also happens in the prepare cycle.
//
// Default (define commented out) - EARLY timing:
//   capture = cycle 1, prepare = cycle 2, write = cycle 3 (clk_counter 001/010/011).
//   Only one counter bit changes between the prepare and write cycles, so the
//   address mux select cannot glitch between them.
//
// `define SRAM_WRITE_LATE - LATE timing:
//   capture = cycle 2, prepare = cycle 3, write = cycle 4 (clk_counter 010/011/100).
//   All three counter bits change between prepare and write, which can produce a
//   brief glitch on the address mux select and may need slightly more logic.
//   The ULA control register write also happens one cycle later.
//
// Both timings give the SRAM one full cycle of address setup before nWE falls.
//`define SRAM_WRITE_LATE

module VideoULA (
    // Clocks
    input  wire        CLK_IN,
    output wire        CLK_8M,
    output wire        CLK_4M,
    output wire        CLK_2M,
    output wire        CLK_1M,
    output wire        CLK_CRTC,
    // 6MHz output: drives SAA5050 in both modes
    output wire        CLK_6M,
    // Bus interface
    input  wire        nCS,
    input  wire        A,
    input  wire [7:0]  D,
    // Control interface
    input  wire        DISEN,
    input  wire        CURSOR,
    // Video in (teletext mode)
    input  wire        R_IN,
    input  wire        G_IN,
    input  wire        B_IN,
    // Video out
    output wire        R,
    output wire        G,
    output wire        B,
    // External palette SRAM interface
    output wire [3:0]  SRAM_ADDR,
    inout  wire [3:0]  SRAM_DATA,
`ifdef CLK_AUTO
    inout  wire        SRAM_nWE   // power-up mode strap, then the nWE output
`else
    output wire        SRAM_nWE
`endif
);

    // -------------------------------------------------------------------------
    // ULA control register (R0) fields
    // -------------------------------------------------------------------------
    reg        r0_cursor0    = 1'b0;
    reg        r0_cursor1    = 1'b0;
    reg        r0_cursor2    = 1'b0;
    reg        r0_crtc_2mhz = 1'b0;
    reg [1:0]  r0_pixel_rate = 2'b00;
    reg        r0_teletext   = 1'b0;
    reg        r0_flash      = 1'b0;

    // -------------------------------------------------------------------------
    // Pixel shift register & CRTC display enable latch
    // -------------------------------------------------------------------------
    reg [7:0] pixel_reg  = 8'hFF;
    reg       crtc_disen = 1'b0;

    // -------------------------------------------------------------------------
    // Clock divider
    // -------------------------------------------------------------------------
    reg [3:0] clk_counter = 4'b0000;

    // mhz16_clken: enables clk_counter increment at 16MHz rate
    // 16MHz mode: always 1 (every CLK_IN tick)
    // 48MHz mode: clk_prescaler[1] (every 3rd CLK_IN tick)
    wire mhz16_clken;

`ifdef CLK_AUTO
    // -------------------------------------------------------------------------
    // CLK_AUTO: unified 16MHz / 48MHz build (V01 Rev01 with a fixed pull-up,
    // and Rev02-Rev04 with the JP2 strap)
    // At power-up SRAM_nWE is released (high-Z) and a 10K strap pulls it up
    // (48MHz) or down (16MHz). The pin is watched for a start-up window of
    // 2^START_BITS CLK_IN cycles (512 cycles = 10.7us at 48MHz, 32us at 16MHz),
    // then becomes the normal nWE output.
    // 48MHz is selected if the pin reads high on two consecutive cycles at any
    // point in the window ("sticky high"). The strap rises with the supply
    // over several ms, and the CPLD can start while it is still close to the
    // input threshold, so a single sample at the end of the window could read
    // low. A strap pulled to ground never reads high, and requiring two
    // consecutive highs ignores single-cycle glitches.
    // The clock dividers are held at zero until the window ends, so the clock
    // phases start in the same state in both modes. Power-cycle after changing
    // JP1/JP2. A longer window costs one macrocell per extra bit.
    // -------------------------------------------------------------------------
    localparam START_BITS = 9;

    reg [START_BITS-1:0] start_cnt = {START_BITS{1'b0}};
    reg                  started   = 1'b0;
    reg                  sel48     = 1'b0;
    reg                  strap_q   = 1'b0;

`ifdef CLK_AUTO_INVERT_STRAP
    wire strap48 = ~SRAM_nWE;
`else
    wire strap48 =  SRAM_nWE;
`endif

    always @(posedge CLK_IN)
        if (!started) begin
            start_cnt <= start_cnt + 1'b1;
            strap_q   <= strap48;
            if (strap48 & strap_q) sel48 <= 1'b1;
            if (&start_cnt)        started <= 1'b1;
        end

    // 48MHz mode: prescaler and 6MHz state decode (as in the CLK_48MHZ build)
    reg [1:0] clk_prescaler = 2'b00;
    reg       clk_6m_reg    = 1'b0;

    always @(posedge CLK_IN) begin
        if (clk_prescaler[1])
            clk_prescaler <= 2'b00;
        else
            clk_prescaler <= clk_prescaler + 1'b1;
    end

    always @(posedge CLK_IN) begin
        (* parallel_case *)
        case ({clk_counter, clk_prescaler})
            6'b000010, 6'b001101, 6'b011000,
            6'b100010, 6'b101101, 6'b111000:
                clk_6m_reg <= 1'b0;
            6'b001000, 6'b010010, 6'b011101,
            6'b101000, 6'b110010, 6'b111101:
                clk_6m_reg <= 1'b1;
            default: ; // hold current value
        endcase
    end

    // 16MHz mode: CLK_6M from both edges of CLK_IN (as in the CLK_16MHZ build)
    // tgl_pos and tgl_neg are pure functions of clk_counter[2:0] (the same count
    // that gives CLK_1M), not free-running toggles with their own counter, so the
    // 6MHz can never lose its phase against the 1MHz. Identical output to the
    // earlier toggle version (checked half-cycle by half-cycle).
    reg tgl_pos = 1'b1;
    reg tgl_neg = 1'b0;

    always @(posedge CLK_IN)
        if (started)
            tgl_pos <= ~(clk_counter[2:0] == 3'd0 || clk_counter[2:0] == 3'd4);

    always @(negedge CLK_IN)
        tgl_neg <= (clk_counter[2:0] >= 3'd3 && clk_counter[2:0] <= 3'd6);

    assign mhz16_clken = started & (~sel48 | clk_prescaler[1]);
    assign CLK_6M      = sel48 ? clk_6m_reg : (tgl_pos ^ tgl_neg);

`else // not CLK_AUTO
`ifdef CLK_48MHZ
    reg [1:0] clk_prescaler = 2'b00;
    reg       clk_6m_reg    = 1'b0;

    // 2-bit prescaler: counts 00,01,10,00,01,10...
    // MSB (clk_prescaler[1]) becomes mhz16_clken
    always @(posedge CLK_IN) begin
        if (clk_prescaler[1])
            clk_prescaler <= 2'b00;
        else
            clk_prescaler <= clk_prescaler + 1'b1;
    end

    // CLK_6M generation from {clk_counter, clk_prescaler} state.
    // 48 states total (16 x 3). CLK_6M toggles every 4 states = 6MHz.
    // Phase locked: CLK_6M rises at state 1111_01 (20.83ns before CLK_1M falls)
    // tD = 20.83ns, within SAA5050 requirement of 6-60ns. ✓
    //
    // State table (clk_counter_clk_prescaler -> clk_6m_reg action):
    // 0000_10, 0011_01, 0110_00, 1000_10, 1011_01, 1110_00 -> 0
    // 0010_00, 0100_10, 0111_01, 1010_00, 1100_10, 1111_01 -> 1
    always @(posedge CLK_IN) begin
        (* parallel_case *)
        case ({clk_counter, clk_prescaler})
            6'b000010, 6'b001101, 6'b011000,
            6'b100010, 6'b101101, 6'b111000:
                clk_6m_reg <= 1'b0;
            6'b001000, 6'b010010, 6'b011101,
            6'b101000, 6'b110010, 6'b111101:
                clk_6m_reg <= 1'b1;
            default: ; // hold current value
        endcase
    end

    assign mhz16_clken = clk_prescaler[1];
    assign CLK_6M      = clk_6m_reg;

`else
    assign mhz16_clken = 1'b1;

    // CLK_6M from CLK_IN (16MHz): 6 edges per 8 clocks (3,3,2,3,3,2 half-cycles).
    // tgl_pos and tgl_neg are pure functions of clk_counter[2:0] (the same count
    // that gives CLK_1M), so the phase relative to CLK_1M is fixed by
    // construction and cannot be lost. tD (6MHz rise to 1MHz fall) is about
    // 31ns; SAA5050 requires 6-60ns.
    reg tgl_pos = 1'b1;
    reg tgl_neg = 1'b0;

    // Rising-edge domain
    always @(posedge CLK_IN)
        tgl_pos <= ~(clk_counter[2:0] == 3'd0 || clk_counter[2:0] == 3'd4);

    // Falling-edge domain
    always @(negedge CLK_IN)
        tgl_neg <= (clk_counter[2:0] >= 3'd3 && clk_counter[2:0] <= 3'd6);

    assign CLK_6M = tgl_pos ^ tgl_neg;
`endif
`endif // CLK_AUTO

    // clk_counter: increments at 16MHz rate in both modes
    always @(posedge CLK_IN)
        if (mhz16_clken)
            clk_counter <= clk_counter + 1'b1;

    assign CLK_8M   = clk_counter[0];
    assign CLK_4M   = clk_counter[1];
    assign CLK_2M   = clk_counter[2];
    assign CLK_1M   = clk_counter[3];
    assign CLK_CRTC = r0_crtc_2mhz ? clk_counter[2] : clk_counter[3];

    // -------------------------------------------------------------------------
    // Clock enables
    // -------------------------------------------------------------------------
    // SRAM palette write: address loaded in the capture cycle, address driven
    // in the prepare cycle, nWE low and data driven in the write cycle.
`ifdef SRAM_WRITE_LATE
    localparam [2:0] WR_CAPTURE = 3'd2, WR_PREP = 3'd3, WR_DO = 3'd4;
`else
    localparam [2:0] WR_CAPTURE = 3'd1, WR_PREP = 3'd2, WR_DO = 3'd3;
`endif
    wire r0_data_ready    = (~nCS) & (clk_counter[2:0] == WR_CAPTURE);
    wire r0_prepare_write = (~nCS) & (clk_counter[2:0] == WR_PREP);
    wire r0_do_write      = (~nCS) & (clk_counter[2:0] == WR_DO);

    // crtc_clken: fires at posedge end of DRAM access cycle x111/x1111
    // DRAM nCAS asserted at x110 (via IC45), data valid after ~67ns.
    // 67ns < 125ns (2 cycles at 16MHz), so data valid by end of x111. ✓
    wire crtc_clken = (r0_crtc_2mhz  & (clk_counter[2:0] == 3'b111)) |
                      (~r0_crtc_2mhz & (clk_counter[3:0] == 4'b1111));

    // pixel_clken: fires at end of each pixel period, aligned with x111
    wire pixel_clken =
        (r0_pixel_rate == 2'b11) ? 1'b1 :
        (r0_pixel_rate == 2'b10) ? clk_counter[0] :
        (r0_pixel_rate == 2'b01) ? (clk_counter[0] & clk_counter[1]) :
                                   (clk_counter[0] & clk_counter[1] & clk_counter[2]);

    // -------------------------------------------------------------------------
    // Register writes
    // -------------------------------------------------------------------------
    always @(posedge CLK_IN) begin
        if (mhz16_clken) begin
            if (r0_prepare_write & ~A) begin
                r0_cursor0    <= D[7];
                r0_cursor1    <= D[6];
                r0_cursor2    <= D[5];
                r0_crtc_2mhz <= D[4];
                r0_pixel_rate <= D[3:2];
                r0_teletext   <= D[1];
                r0_flash      <= D[0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // External SRAM palette interface
    // Palette write is split over two cycles. In the prepare cycle the
    // address (from sram_addr_reg) is driven while nWE is still high. nWE then
    // goes low in the following cycle, so the address is stable before nWE.
    // SRAM_DATA is only driven during the nWE cycle, so the CPLD does not
    // fight the SRAM output (SRAM /OE is tied low).
    // sram_addr_reg is loaded from D[7:4] in the cycle before the prepare cycle.
    // -------------------------------------------------------------------------
    wire sram_pre_write = r0_prepare_write & A;
    wire sram_do_write  = r0_do_write & A;
    wire sram_busy      = sram_pre_write | sram_do_write;

    reg [3:0] sram_addr_reg = 4'b0000;
    always @(posedge CLK_IN)
        if (mhz16_clken & r0_data_ready)
            sram_addr_reg <= D[7:4];

    wire [3:0] log_col = {pixel_reg[7], pixel_reg[5], pixel_reg[3], pixel_reg[1]};

    assign SRAM_ADDR = sram_busy ? sram_addr_reg : log_col;
`ifdef CLK_AUTO
    assign SRAM_nWE  = started ? ~sram_do_write : 1'bz;
`else
    assign SRAM_nWE  = ~sram_do_write;
`endif

    // Data-bus enable is registered: set in the prepare cycle, so it is high
    // for the nWE cycle only.
    reg sram_oe_reg = 1'b0;
    always @(posedge CLK_IN)
        if (mhz16_clken) sram_oe_reg <= sram_pre_write;
    assign SRAM_DATA = sram_oe_reg ? D[3:0] : 4'bZZZZ;

    wire [3:0] phy_col = SRAM_DATA;

    // -------------------------------------------------------------------------
    // Pixel shift register
    // Posedge sampling at end of DRAM access cycle x111.
    // DRAM (HM4816A-3) data valid by end of x111 - ideal sample point.
    // All logic on posedge - no mixed-edge clocking, no BUFG warnings.
    // -------------------------------------------------------------------------
    always @(posedge CLK_IN) begin
        if (mhz16_clken) begin
            if (pixel_clken) begin
                if (crtc_clken) begin
                    pixel_reg  <= D;
                    crtc_disen <= DISEN;
                end else begin
                    pixel_reg  <= {pixel_reg[6:0], 1'b1};
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Cursor generation
    // -------------------------------------------------------------------------
    reg [3:0] cursor_invert = 4'b0000;
    reg       cursor_active  = 1'b0;
    reg [1:0] cursor_counter = 2'b00;

    wire cursor_invert0 = cursor_active &
                          ((r0_cursor0 & ~cursor_counter[0] & ~cursor_counter[1]) |
                           (r0_cursor1 &  cursor_counter[0] & ~cursor_counter[1]) |
                           (r0_cursor2 &  cursor_counter[1]));

    always @(posedge CLK_IN) begin
        if (mhz16_clken) begin
            cursor_invert[0] <= cursor_invert0;
            cursor_invert[1] <= cursor_invert[0];
            cursor_invert[2] <= cursor_invert[1];
            cursor_invert[3] <= cursor_invert[2];
            if (crtc_clken) begin
                if (CURSOR | cursor_active) begin
                    cursor_active <= 1'b1;
                    if (cursor_counter == 2'b11)
                        cursor_active <= 1'b0;
                    cursor_counter <= cursor_active ? cursor_counter + 1'b1 : 2'b00;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Pixel generation
    // sram_busy gates the output for both palette write cycles so they don't
    // corrupt the current pixel - SRAM_ADDR and SRAM_DATA belong to the write
    // so phy_col would be invalid.
    // -------------------------------------------------------------------------
    wire red_val   = (phy_col[3] & r0_flash) ^ ~phy_col[0];
    wire green_val = (phy_col[3] & r0_flash) ^ ~phy_col[1];
    wire blue_val  = (phy_col[3] & r0_flash) ^ ~phy_col[2];

    reg RR = 1'b0;
    reg GG = 1'b0;
    reg BB = 1'b0;

    always @(posedge CLK_IN) begin
        if (mhz16_clken) begin
            if (~sram_busy) begin  // hold RGB during both palette write cycles
                // Modes 0-6: cursor_invert0 has no delay, so the cursor lines up
                // with the palette lookup latency. Do not use cursor_invert0 in
                // the teletext mux below as well: routing both may fail to fit.
                RR <= (red_val   & crtc_disen) ^ cursor_invert0;
                GG <= (green_val & crtc_disen) ^ cursor_invert0;
                BB <= (blue_val  & crtc_disen) ^ cursor_invert0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output mux
    // -------------------------------------------------------------------------
    // Mode 7: cursor_invert[0] (62.5ns) gives a correctly aligned cursor
    // with the CPLD generating the 6MHz (as on V02/V03).
    assign R = r0_teletext ? (R_IN ^ cursor_invert[0]) : RR;
    assign G = r0_teletext ? (G_IN ^ cursor_invert[0]) : GG;
    assign B = r0_teletext ? (B_IN ^ cursor_invert[0]) : BB;

endmodule
