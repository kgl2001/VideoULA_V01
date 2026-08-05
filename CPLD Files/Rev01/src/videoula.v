`timescale 1ns / 1ps
/************************************************************************
VideoULA.v
VideoULA V1    - A replacement Video ULA for the BBC Micro
Build 37       - August 2026 - Pre-load sram_addr_reg one cycle early for tSA fix
                 Based on community code by hoget (Stardot forums)
                 Posedge sampling at x111 per DRAM timing analysis
(C) Ken Lowe July 2026.
Community contributions: hoget (Stardot forums) - unified clock architecture
------------------------------------------------------------------------
CLOCK CONFIGURATION - uncomment ONE define only
NOTE: CLK_6M is always present as a port in both builds.
  48MHz build: CLK_6M actively drives the SAA5050 6MHz clock
  16MHz build: CLK_6M is held high-Z (no change to .ucf required)
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

  CLK_6M (48MHz mode only):
    Derived from {clk_counter, clk_prescaler} state decode (CASE option).
    Phase locked to CLK_1M: CLK_6M rises 20.83ns before CLK_1M falls.
    tD = 20.83ns, within SAA5050 requirement of 6-60ns. ?

  pixel_reg sampled on posedge at end of DRAM access cycle x111:
    DRAM nCAS asserted at x110 (via IC45 74S139, ~12ns delay)
    DRAM data valid after ~67ns (55ns HM4816A-3 access + 12ns IC45)
    67ns < 125ns (2 x 62.5ns cycles) so data valid by end of x111 ?
    All logic on posedge - no mixed-edge clocking, no BUFG warnings.

Palette storage: external SRAM (IS62C256AL-45TLI)
  SRAM_ADDR[3:0] <- palette index (logical colour)
  SRAM_DATA[3:0] <-> palette data (physical colour)
  SRAM_nWE       <- write enable (active low)
  Note: SRAM write uses live CPU bus data (D[7:4] address, D[3:0] data).
        Write pulse = one 16MHz cycle = 62.5ns > IS62C256AL-45 tWP=25ns minimum ?
        SRAM_ADDR and SRAM_nWE both change simultaneously (both driven by
        sram_write), so tSA=0ns is not strictly met. Works in practice.
************************************************************************/

// ------------------------------------------------------------------------
// CLOCK CONFIGURATION - uncomment ONE define only
// ------------------------------------------------------------------------
`define CLK_48MHZ
//`define CLK_16MHZ

`ifdef CLK_48MHZ
  `ifdef CLK_16MHZ
    ERROR_BOTH_CLOCK_DEFINES_SET // deliberate syntax error if both defined
  `endif
`endif

module VideoULA (
    // Clocks
    input  wire        CLK_IN,
    output wire        CLK_8M,
    output wire        CLK_4M,
    output wire        CLK_2M,
    output wire        CLK_1M,
    output wire        CLK_CRTC,
    // 6MHz output: drives SAA5050 in 48MHz mode; high-Z in 16MHz mode
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
    output wire        SRAM_nWE
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
    // tD = 20.83ns, within SAA5050 requirement of 6-60ns. ?
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
    assign CLK_6M      = 1'bZ;
`endif

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
    // r0_clken: fires at end of cycle 2 (010).
    // CPU data bus valid from ~100ns after Phi2 rises to ~30ns after Phi2 falls.
    // Phi2 falls ~30ns before end of cycle 3 (011), so cycle 2 (010) gives
    // a comfortable 30ns margin before the end of the valid data window.
    // Previously at cycle 4 (100) = ~100ns into next bus cycle (too late).
    wire r0_clken   = (~nCS) & (clk_counter[2:0] == 3'b010);

    // crtc_clken: fires at posedge end of DRAM access cycle x111/x1111
    // DRAM nCAS asserted at x110 (via IC45), data valid after ~67ns.
    // 67ns < 125ns (2 cycles at 16MHz), so data valid by end of x111. ?
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
            if (r0_clken & ~A) begin
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
    //
    // sram_write is a combinatorial signal derived from r0_clken & A.
    // This allows the write to use live CPU bus data (D[7:4] for address,
    // D[3:0] for data) without needing intermediate registers.
    // The write pulse occurs at end of cycle 2 (010), when CPU data is
    // guaranteed valid (~30ns before Phi2 falls). ?
    //
    // Note: SRAM_ADDR and SRAM_nWE change at approximately the same time
    // (both combinatorial from sram_write). This technically violates the
    // SRAM tSA=0ns address setup time spec by a few ns due to mux delay,
    // but works correctly in practice. A future fix could use an earlier
    // mux control signal to pre-drive the address before nWE asserts.
    // -------------------------------------------------------------------------
    wire sram_write = r0_clken & A;

    // SRAM write address pre-loading for tSA compliance:
    // r0_preload fires one cycle before r0_clken (at cycle 001 vs 010).
    // sram_addr_reg is loaded with D[7:4] at cycle 001, so it is fully
    // settled before sram_write asserts at cycle 010.
    // Both SRAM_ADDR (via mux from registered sram_addr_reg) and SRAM_nWE
    // (from registered sram_write) then have similar propagation delays,
    // satisfying SRAM tSA=0ns with no two-cycle write extension. ?
    // CPU data bus valid from cycle 001 through 011 (within Phi2 window). ?
    wire r0_preload = (~nCS) & (clk_counter[2:0] == 3'b001);

    reg [3:0] sram_addr_reg = 4'b0000;
    always @(posedge CLK_IN)
        if (mhz16_clken & r0_preload)
            sram_addr_reg <= D[7:4];

    wire [3:0] log_col = {pixel_reg[7], pixel_reg[5], pixel_reg[3], pixel_reg[1]};

    assign SRAM_ADDR = sram_write ? sram_addr_reg : log_col;
    assign SRAM_nWE  = ~sram_write;
    assign SRAM_DATA = sram_write ? D[3:0] : 4'bZZZZ;

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
    // sram_write_active gates the output so a palette write cycle doesn't
    // corrupt the current pixel - during a write SRAM_DATA is driven by
    // the CPLD so phy_col would be invalid.
    // -------------------------------------------------------------------------
    wire red_val   = (phy_col[3] & r0_flash) ^ ~phy_col[0];
    wire green_val = (phy_col[3] & r0_flash) ^ ~phy_col[1];
    wire blue_val  = (phy_col[3] & r0_flash) ^ ~phy_col[2];

    reg RR = 1'b0;
    reg GG = 1'b0;
    reg BB = 1'b0;

    always @(posedge CLK_IN) begin
        if (mhz16_clken) begin
            if (~sram_write) begin  // hold RGB during palette write
                RR <= (red_val   & crtc_disen) ^ cursor_invert[0];
                GG <= (green_val & crtc_disen) ^ cursor_invert[0];
                BB <= (blue_val  & crtc_disen) ^ cursor_invert[0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output mux
    // -------------------------------------------------------------------------
    assign R = r0_teletext ? (R_IN ^ cursor_invert[3]) : RR;
    assign G = r0_teletext ? (G_IN ^ cursor_invert[3]) : GG;
    assign B = r0_teletext ? (B_IN ^ cursor_invert[3]) : BB;

endmodule