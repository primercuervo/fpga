#
# Copyright 2017 Ettus Research, A National Instruments Company
# SPDX-License-Identifier: LGPL-3.0
#
# Timing analysis is performed in "/n3xx/doc/mb_timing.xlsx". See
# the spreadsheet for more details and explanations.

#*******************************************************************************
## Motherboard Clocks

# 10/20/25 MHz reference clock from rear panel connector. Constrain to the fastest
# possible clock rate.
set REF_CLK_PERIOD 40.00
create_clock -name ref_clk       -period $REF_CLK_PERIOD  [get_ports FPGA_REFCLK_P]
# 125 MHz RJ45 Ethernet clock
create_clock -name ge_phy_clk    -period 8.000            [get_ports ENET0_CLK125]
# 156.25 MHz oscillator to MGT bank 110
create_clock -name xge_clk       -period 6.400            [get_ports MGT156MHZ_CLK1_P]
# 125 MHz PLL for MG bank 109
create_clock -name net_clk       -period 8.000            [get_ports NETCLK_P]

# Virtual clocks for constraining I/O (used below)
create_clock -name async_in_clk  -period 50.00
create_clock -name async_out_clk -period 50.00



#*******************************************************************************
## Aliases for auto-generated clocks

# Rename the PS clocks. These are originally declared in the PS7 IP block, but do not
# have super descriptive names. We rename them here for additional clarity, and to match
# the rest of the design.

# First save off the input jitter setting for each, before we nuke the original clocks.
set clk100_jitter       [get_property INPUT_JITTER [get_clocks clk_fpga_0]]
set clk40_jitter        [get_property INPUT_JITTER [get_clocks clk_fpga_1]]
set meas_clk_ref_jitter [get_property INPUT_JITTER [get_clocks clk_fpga_2]]
set bus_clk_jitter      [get_property INPUT_JITTER [get_clocks clk_fpga_3]]

# Create the new clocks based on the old ones. This generates critical warnings that
# we are completely rewriting the old clock definition... this is OK.
create_clock -name clk100 \
             -period   [get_property PERIOD      [get_clocks clk_fpga_0]] \
             [get_pins [get_property SOURCE_PINS [get_clocks clk_fpga_0]]]
create_clock -name clk40 \
             -period   [get_property PERIOD      [get_clocks clk_fpga_1]] \
             [get_pins [get_property SOURCE_PINS [get_clocks clk_fpga_1]]]
create_clock -name meas_clk_ref \
             -period   [get_property PERIOD      [get_clocks clk_fpga_2]] \
             [get_pins [get_property SOURCE_PINS [get_clocks clk_fpga_2]]]
create_clock -name bus_clk \
             -period   [get_property PERIOD      [get_clocks clk_fpga_3]] \
             [get_pins [get_property SOURCE_PINS [get_clocks clk_fpga_3]]]

# Apply the jitter setting from the original clocks.
set_input_jitter [get_clocks clk100]       $clk100_jitter
set_input_jitter [get_clocks clk40]        $clk40_jitter
set_input_jitter [get_clocks meas_clk_ref] $meas_clk_ref_jitter
set_input_jitter [get_clocks bus_clk]      $bus_clk_jitter


# TDC Measurement Clock
create_generated_clock -name meas_clk_fb [get_pins {n3xx_clocking_i/misc_clock_gen_i/inst/mmcm_adv_inst/CLKFBOUT}]
create_generated_clock -name meas_clk    [get_pins {n3xx_clocking_i/misc_clock_gen_i/inst/mmcm_adv_inst/CLKOUT0}]



#*******************************************************************************
## Asynchronous clock groups

# All the clocks from the PS are async to everything else except clocks generated
# from themselves.
set_clock_groups -asynchronous -group [get_clocks clk100       -include_generated_clocks]
set_clock_groups -asynchronous -group [get_clocks clk40        -include_generated_clocks]
set_clock_groups -asynchronous -group [get_clocks bus_clk      -include_generated_clocks]
set_clock_groups -asynchronous -group [get_clocks meas_clk_ref -include_generated_clocks]



#*******************************************************************************
## PPS Input Timing

# The external PPS is synchronous to the external reference clock, which is expected to
# be at 10 MHz. Given [setup, hold] of [5ns, 5ns] at the rear panel inputs of the N310,
# we have an adequate data valid window at the FPGA. However, since we overconstrain the
# reference clock to 25 MHz, we use the alternative period here for setup analysis.
set_input_delay -clock ref_clk -min  5.181                           [get_ports REF_1PPS_IN]
set_input_delay -clock ref_clk -max [expr {$REF_CLK_PERIOD - 1.235}] [get_ports REF_1PPS_IN]

# The GPS PPS is also synchronous to the external reference clock (since there is a
# switch on the clock input outside the FPGA). Again, use the overconstrained period.
set_input_delay -clock ref_clk -min  1.234                           [get_ports GPS_1PPS]
set_input_delay -clock ref_clk -max [expr {$REF_CLK_PERIOD - 2.111}] [get_ports GPS_1PPS]



#*******************************************************************************
## MB Async Ins/Outs

set ASYNC_MB_INPUTS [get_ports {SFP_*_LOS SFP_*_TXFAULT UNUSED_PIN_TDC*}]

set_input_delay -clock [get_clocks async_in_clk] 0.000 $ASYNC_MB_INPUTS
set_max_delay -from $ASYNC_MB_INPUTS 50.000
set_min_delay -from $ASYNC_MB_INPUTS 0.000


# REF_1PPS_OUT is included in this list because timing is not currently analyzed on this
# output circuit. It would be possible to analyze the board trace delays and compute the
# data valid window on the output compared to the reference clock input... but that
# is #FutureWork for another day.
set ASYNC_MB_OUTPUTS [get_ports {*LED* SFP_*TXDISABLE UNUSED_PIN_TDC* \
                               FPGA_TEST[*] REF_1PPS_OUT}]

set_output_delay -clock [get_clocks async_out_clk] 0.000 $ASYNC_MB_OUTPUTS
set_max_delay -to $ASYNC_MB_OUTPUTS 50.000
set_min_delay -to $ASYNC_MB_OUTPUTS 0.000

