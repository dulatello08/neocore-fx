//
// neocorefx_pll_40mhz.sv
// NeoCoreFX - ECP5 PLL wrapper (25 MHz -> 40 MHz)
//

module neocorefx_pll_40mhz (
    input  logic clk_i,
    output logic clk_o,
    output logic locked_o
);
    timeunit 1ns;
    timeprecision 1ps;

    (* FREQUENCY_PIN_CLKI = "25" *)
    (* FREQUENCY_PIN_CLKOP = "40" *)
    (* ICP_CURRENT = "12" *)
    (* LPF_RESISTOR = "8" *)
    (* MFG_ENABLE_FILTEROPAMP = "1" *)
    (* MFG_GMCREF_SEL = "2" *)
    EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(5),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(15),
        .CLKOP_CPHASE(7),
        .CLKOP_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(8)
    ) u_pll (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clk_i),
        .CLKOP(clk_o),
        .CLKFB(clk_o),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(locked_o)
    );
endmodule : neocorefx_pll_40mhz
