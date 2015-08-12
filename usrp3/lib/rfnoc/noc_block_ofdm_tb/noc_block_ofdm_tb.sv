//
// Copyright 2015 Ettus Research LLC
//
`timescale 1ns/1ps
`define SIM_RUNTIME_US 1000
`define NS_PER_TICK 1
`define NUM_TEST_CASES 2

`include "sim_exec_report.vh"
`include "sim_rfnoc_lib.vh"

module noc_block_ofdm_tb();
  `TEST_BENCH_INIT("noc_block_ofdm_tb",`NUM_TEST_CASES,`NS_PER_TICK);
  `RFNOC_SIM_INIT(5,166.67,200);
  `RFNOC_ADD_BLOCK(noc_block_file_source,0);
  defparam noc_block_file_source.FILENAME = "../../../../ofdm_test_vectors.dat";
  `RFNOC_ADD_BLOCK(noc_block_schmidl_cox,1);
  `RFNOC_ADD_BLOCK(noc_block_fft,2);
  defparam noc_block_fft.EN_MAGNITUDE_OUT        = 0;
  defparam noc_block_fft.EN_MAGNITUDE_APPROX_OUT = 0;
  defparam noc_block_fft.EN_MAGNITUDE_SQ_OUT     = 0;
  defparam noc_block_fft.EN_FFT_SHIFT            = 1;
  `RFNOC_ADD_BLOCK(noc_block_eq,3);
  `RFNOC_ADD_BLOCK(noc_block_ofdm_constellation_demapper,4);
  defparam noc_block_ofdm_constellation_demapper.NUM_SUBCARRIERS      = 64;
  defparam noc_block_ofdm_constellation_demapper.EXCLUDE_SUBCARRIERS  = 64'b1111_1100_0001_0000_0000_0000_0100_0000_1000_0001_0000_0000_0000_0100_0001_1111;
  defparam noc_block_ofdm_constellation_demapper.MAX_MODULATION_ORDER = 6;

  localparam [31:0] OFDM_SYMBOL_SIZE = 64;
  localparam [31:0] PACKET_LENGTH    = 4;
  localparam [31:0] NUM_PACKETS      = 10;

  // FFT specific settings
  localparam [15:0] FFT_SIZE  = OFDM_SYMBOL_SIZE;
  wire [7:0] fft_size_log2    = $clog2(FFT_SIZE);        // Set FFT size
  wire fft_direction          = 0;                       // Set FFT direction to forward (i.e. DFT[x(n)] => X(k))
  //wire [11:0] fft_scale       = 12'b011010101010;        // Conservative scaling (1/N)
  wire [11:0] fft_scale       = 12'b000100000001;        // Aggressive scaling
  wire [20:0] fft_ctrl_word   = {fft_scale, fft_direction, fft_size_log2};

  cvita_pkt_t  pkt;
  logic [63:0] header;
  logic [15:0] real_val;
  logic [15:0] cplx_val;
  logic last;

  /********************************************************
  ** Verification
  ********************************************************/
  initial begin : tb_main
    `TEST_CASE_START("Wait for reset");
    while (bus_rst) @(posedge bus_clk);
    while (ce_rst) @(posedge ce_clk);
    `TEST_CASE_DONE(~bus_rst & ~ce_rst);
    `TEST_CASE_START("Receive & check data");
    for (int n = 0; n < NUM_PACKETS; n = n + 1) begin
      for (int l = 0; l < PACKET_LENGTH; l = l + 1) begin
        for (int k = 0; k < OFDM_SYMBOL_SIZE; k = k + 1) begin
          tb_axis_data.pull_word({real_val,cplx_val},last);
        end
      end
    end
    `TEST_CASE_DONE(1);
  end

  /*********************************************************************
   ** Connect and setup RFNoC blocks 
   *********************************************************************/
  initial begin
    while (bus_rst) @(posedge bus_clk);
    while (ce_rst) @(posedge ce_clk);

    repeat (10) @(posedge bus_clk);

    // File Source -> Schmidl Cox -> FFT -> Test bench
    `RFNOC_CONNECT(noc_block_file_source,noc_block_schmidl_cox,OFDM_SYMBOL_SIZE*4);
    `RFNOC_CONNECT(noc_block_schmidl_cox,noc_block_fft,OFDM_SYMBOL_SIZE*4);
    `RFNOC_CONNECT(noc_block_fft,noc_block_eq,OFDM_SYMBOL_SIZE*4);
    `RFNOC_CONNECT(noc_block_eq,noc_block_ofdm_constellation_demapper,OFDM_SYMBOL_SIZE*4);
    `RFNOC_CONNECT(noc_block_ofdm_constellation_demapper,noc_block_tb,OFDM_SYMBOL_SIZE*4);

    tb_cvita_ack.axis.tready = 1'b1;  // Drop all response packets

    // Setup File Source
    header = flatten_chdr_no_ts('{pkt_type:CMD, has_time:0, eob:0, seqno:12'h0, length:8, src_sid:sid_noc_block_tb, dst_sid:sid_noc_block_file_source, timestamp:64'h0});
    tb_cvita_cmd.push_pkt({header, {noc_block_file_source.file_source.SR_PKT_LENGTH, 32'd180}});   // Length, 180 is about the size of a typical Ethernet packet with MTU 1500
    tb_cvita_cmd.push_pkt({header, {noc_block_file_source.file_source.SR_RATE, 32'd10}});          // Output every 10th cycle (assuming 200 MHz radio_clk & 20 MHz BW)

    // Setup Schmidl Cox
    header = flatten_chdr_no_ts('{pkt_type:CMD, has_time:0, eob:0, seqno:12'h0, length:8, src_sid:sid_noc_block_tb, dst_sid:sid_noc_block_schmidl_cox, timestamp:64'h0});
    tb_cvita_cmd.push_pkt({header, {noc_block_schmidl_cox.schmidl_cox.SR_FRAME_LEN, OFDM_SYMBOL_SIZE}});        // FFT Size
    tb_cvita_cmd.push_pkt({header, {noc_block_schmidl_cox.schmidl_cox.SR_GAP_LEN, 32'd16}});                    // Cyclic Prefix length
    tb_cvita_cmd.push_pkt({header, {noc_block_schmidl_cox.schmidl_cox.SR_OFFSET, {32'd0-14+32+64}}});           // Calibrated delay to start at beginning of second long preamble (pipeline delay + 2 cyclic prefixes + 1 symbol)
    tb_cvita_cmd.push_pkt({header, {noc_block_schmidl_cox.schmidl_cox.SR_NUMBER_SYMBOLS_MAX, PACKET_LENGTH}});  // Maximum number of symbols (excluding preamble)
    tb_cvita_cmd.push_pkt({header, {noc_block_schmidl_cox.schmidl_cox.SR_NUMBER_SYMBOLS_SHORT, 32'd0}});        // Unused
    // Schmidl & Cox algorithm uses a metric normalized between 0.0 - 1.0.
    tb_cvita_cmd.push_pkt({header, {noc_block_schmidl_cox.schmidl_cox.SR_THRESHOLD, 16'd0, 16'd14335}});        // Threshold (format Q1.14, Sign bit, 1 integer, 14 fractional), 14335 ~= +0.875

    // Setup FFT
    header = flatten_chdr_no_ts('{pkt_type:CMD, has_time:0, eob:0, seqno:12'h0, length:8, src_sid:sid_noc_block_tb, dst_sid:sid_noc_block_fft, timestamp:64'h0});
    tb_cvita_cmd.push_pkt({header, {SR_AXI_CONFIG_BASE, {11'd0, fft_ctrl_word}}});                                // Configure FFT core
    tb_cvita_cmd.push_pkt({header, {24'd0, noc_block_fft.SR_FFT_SIZE_LOG2, {24'd0, fft_size_log2}}});             // Set FFT size register
    tb_cvita_cmd.push_pkt({header, {24'd0, noc_block_fft.SR_MAGNITUDE_OUT, {30'd0, noc_block_fft.COMPLEX_OUT}}}); // Complex FFT data out

    // Setup OFDM constellation demapper for QPSK
    header = flatten_chdr_no_ts('{pkt_type:CMD, has_time:0, eob:0, seqno:12'h0, length:8, src_sid:sid_noc_block_tb, dst_sid:sid_noc_block_ofdm_constellation_demapper, timestamp:64'h0});
    tb_cvita_cmd.push_pkt({header, {noc_block_ofdm_constellation_demapper.SR_MODULATION_ORDER, 32'd2}});                    // QPSK
    tb_cvita_cmd.push_pkt({header, {noc_block_ofdm_constellation_demapper.SR_SCALING, 32'd0 + 23170 }});  // QPSK scaling $floor((2**14)*$sqrt(2))

  end
endmodule
