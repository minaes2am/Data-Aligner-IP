`ifndef ALIGNER_CORE_V
  `define ALIGNER_CORE_V
  module aligner_core#(
    parameter APB_ADDR_WIDTH  = 16,
    parameter ALGN_DATA_WIDTH = 32,
    parameter FIFO_DEPTH      = 8,
    
     //Clock Domain Crossing - RX domain to register access domain
     //Set this parameter to 0 only if md_rx_clk and pclk are tied to the same clock signal.
     parameter CDC_RX_TO_REG  = 1,

     //Clock Domain Crossing - register access domain to TX domain
     //Set this parameter to 0 only if pclk and md_tx_clk are tied to the same clock signal.
     parameter CDC_REG_TO_TX  = 1,

    localparam int unsigned STATUS_CNT_DROP_WIDTH = 8,

    localparam int unsigned APB_DATA_WIDTH  = 32,

    localparam int unsigned ALGN_OFFSET_WIDTH = ALGN_DATA_WIDTH <= 8 ? 1 : $clog2(ALGN_DATA_WIDTH/8),
    localparam int unsigned ALGN_SIZE_WIDTH   = $clog2(ALGN_DATA_WIDTH/8)+1
  ) (
    input wire pclk,
    input wire preset_n,

    input wire[APB_ADDR_WIDTH-1:0]    paddr,
    input wire                        pwrite,
    input wire                        psel,
    input wire                        penable,
    input wire[APB_DATA_WIDTH-1:0]    pwdata,
    output wire                       pready,
    output reg[APB_DATA_WIDTH-1:0]    prdata,
    output reg                        pslverr,

    input                             md_rx_clk,
    input                             md_rx_valid,
    input[ALGN_DATA_WIDTH-1:0]        md_rx_data,
    input[ALGN_OFFSET_WIDTH-1:0]      md_rx_offset,
    input[ALGN_SIZE_WIDTH-1:0]        md_rx_size,
    output reg                        md_rx_ready,
    output reg                        md_rx_err,

    input                             md_tx_clk,
    output reg                        md_tx_valid,
    output reg[ALGN_DATA_WIDTH-1:0]   md_tx_data,
    output reg[ALGN_OFFSET_WIDTH-1:0] md_tx_offset,
    output reg[ALGN_SIZE_WIDTH-1:0]   md_tx_size,
    input                             md_tx_ready,
    input                             md_tx_err,

    output wire                       irq
  );

    localparam int unsigned FIFO_WIDTH        = ALGN_DATA_WIDTH + ALGN_OFFSET_WIDTH + ALGN_SIZE_WIDTH;
    localparam int unsigned FIFO_LVL_WIDTH    = $clog2(FIFO_DEPTH) + 1;

    initial begin
      assert(APB_ADDR_WIDTH >= 12) else begin
        $error($sformatf("Legal values for APB_ADDR_WIDTH parameter must greater of equal than 12 but found 'd%0d", APB_ADDR_WIDTH));
      end

      assert($countones(ALGN_DATA_WIDTH) == 1) else begin
        $error($sformatf("Legal values for ALGN_DATA_WIDTH parameter must be a power of two but found 'd%0d", ALGN_DATA_WIDTH));
      end

      assert(ALGN_DATA_WIDTH >= 8) else begin
        $error($sformatf("Legal values for ALGN_DATA_WIDTH parameter must be greater or equal than 8 but found 'd%0d", ALGN_DATA_WIDTH));
      end
    end

    wire[STATUS_CNT_DROP_WIDTH-1:0] rx_ctrl_2_regs_status_cnt_drop;
    wire                            regs_2_rx_ctrl_ctrl_clr;
    wire                            rx_ctrl_2_rx_fifo_push_valid;
    wire[FIFO_WIDTH-1:0]            rx_ctrl_2_rx_fifo_push_data;
    wire                            rx_fifo_2_rx_ctrl_push_ready;
    wire                            rx_fifo_2_rx_ctrl_push_full;
    wire                            rx_fifo_2_regs_fifo_full;
    wire                            rx_fifo_2_regs_fifo_empty;
    wire[FIFO_LVL_WIDTH-1:0]        rx_fifo_2_regs_fifo_lvl;
    wire[FIFO_LVL_WIDTH-1:0]        tx_fifo_2_regs_fifo_lvl;
    wire                            tx_fifo_2_regs_fifo_empty;
    wire                            tx_fifo_2_regs_fifo_full;
    wire                            tx_fifo_2_tx_ctrl_pop_valid;
    wire[FIFO_WIDTH-1:0]            tx_fifo_2_tx_ctrl_pop_data;
    wire                            tx_fifo_2_tx_ctrl_pop_ready;
    wire                            rx_fifo_2_ctrl_pop_valid;
    wire[FIFO_WIDTH-1:0]            rx_fifo_2_ctrl_pop_data;
    wire                            rx_fifo_2_ctrl_pop_ready;
    wire                            ctrl_2_tx_fifo_push_valid;
    wire[FIFO_WIDTH-1:0]            ctrl_2_tx_fifo_push_data;
    wire                            ctrl_2_tx_fifo_push_ready;
    wire[ALGN_OFFSET_WIDTH-1:0]     regs_2_ctrl_ctrl_offset;
    wire[ALGN_SIZE_WIDTH-1:0]       regs_2_ctrl_ctrl_size;

    rx_ctrl #(
      .ALGN_DATA_WIDTH      (ALGN_DATA_WIDTH),
      .STATUS_CNT_DROP_WIDTH(STATUS_CNT_DROP_WIDTH)
    ) rx_ctrl (
      .preset_n       (preset_n),
      .pclk           (pclk),

      .status_cnt_drop(rx_ctrl_2_regs_status_cnt_drop),
      .clr_cnt_dop    (regs_2_rx_ctrl_ctrl_clr),

      .md_rx_clk      (md_rx_clk),
      .md_rx_valid    (md_rx_valid),
      .md_rx_data     (md_rx_data),
      .md_rx_offset   (md_rx_offset),
      .md_rx_size     (md_rx_size),
      .md_rx_ready    (md_rx_ready),
      .md_rx_err      (md_rx_err),

      .push_valid     (rx_ctrl_2_rx_fifo_push_valid),
      .push_data      (rx_ctrl_2_rx_fifo_push_data),
      .push_ready     (rx_fifo_2_rx_ctrl_push_ready),

      .rx_fifo_full   (rx_fifo_2_rx_ctrl_push_full)
    );

    synch_fifo #(
      .DATA_WIDTH(FIFO_WIDTH),
      .FIFO_DEPTH(FIFO_DEPTH),
      .CDC(       CDC_RX_TO_REG)) rx_fifo (
      .reset_n      (preset_n),

      .push_clk     (md_rx_clk),
      .push_valid   (rx_ctrl_2_rx_fifo_push_valid),
      .push_data    (rx_ctrl_2_rx_fifo_push_data),
      .push_ready   (rx_fifo_2_rx_ctrl_push_ready),

      .push_full    (rx_fifo_2_rx_ctrl_push_full),

      .push_empty   (),

      .push_fifo_lvl(),

      .pop_clk      (pclk),
      .pop_valid    (rx_fifo_2_ctrl_pop_valid),
      .pop_data     (rx_fifo_2_ctrl_pop_data),
      .pop_ready    (rx_fifo_2_ctrl_pop_ready),

      .pop_full     (rx_fifo_2_regs_fifo_full),

      .pop_empty    (rx_fifo_2_regs_fifo_empty),

      .pop_fifo_lvl (rx_fifo_2_regs_fifo_lvl)
    );

    synch_fifo #(
      .DATA_WIDTH(FIFO_WIDTH),
      .FIFO_DEPTH(FIFO_DEPTH),
      .CDC(       CDC_REG_TO_TX)) tx_fifo (
      .reset_n   (preset_n),

      .push_clk  (pclk),
      .push_valid(ctrl_2_tx_fifo_push_valid),
      .push_data (ctrl_2_tx_fifo_push_data),
      .push_ready(ctrl_2_tx_fifo_push_ready),

      .push_full (tx_fifo_2_regs_fifo_full),

      .push_empty(tx_fifo_2_regs_fifo_empty),

      .push_fifo_lvl(tx_fifo_2_regs_fifo_lvl),

      .pop_clk   (md_tx_clk),
      .pop_valid (tx_fifo_2_tx_ctrl_pop_valid),
      .pop_data  (tx_fifo_2_tx_ctrl_pop_data),
      .pop_ready (tx_fifo_2_tx_ctrl_pop_ready),

      .pop_full  (),

      .pop_empty (),

      .pop_fifo_lvl ()
    );

    tx_ctrl #(
      .ALGN_DATA_WIDTH(ALGN_DATA_WIDTH)
    ) tx_ctrl (
      .pop_valid   (tx_fifo_2_tx_ctrl_pop_valid),
      .pop_data    (tx_fifo_2_tx_ctrl_pop_data),
      .pop_ready   (tx_fifo_2_tx_ctrl_pop_ready),

      .md_tx_valid (md_tx_valid),
      .md_tx_data  (md_tx_data),
      .md_tx_offset(md_tx_offset),
      .md_tx_size  (md_tx_size),
      .md_tx_ready (md_tx_ready)
    );

     ctrl #(
      .ALGN_DATA_WIDTH(ALGN_DATA_WIDTH)
    ) ctrl(
      .reset_n    (preset_n),
      .clk        (pclk),

      .pop_valid  (rx_fifo_2_ctrl_pop_valid),
      .pop_data   (rx_fifo_2_ctrl_pop_data),
      .pop_ready  (rx_fifo_2_ctrl_pop_ready),

      .push_valid (ctrl_2_tx_fifo_push_valid),
      .push_data  (ctrl_2_tx_fifo_push_data),
      .push_ready (ctrl_2_tx_fifo_push_ready),

      .ctrl_offset(regs_2_ctrl_ctrl_offset),
      .ctrl_size  (regs_2_ctrl_ctrl_size)
      );

     regs#(
      .APB_ADDR_WIDTH       (APB_ADDR_WIDTH),
      .STATUS_CNT_DROP_WIDTH(STATUS_CNT_DROP_WIDTH),
      .ALGN_DATA_WIDTH      (ALGN_DATA_WIDTH)) regs (
      .pclk           (pclk),
      .presetn        (preset_n),
      .paddr          (paddr),
      .pwrite         (pwrite),
      .psel           (psel),
      .penable        (penable),
      .pwdata         (pwdata),
      .pready         (pready),
      .prdata         (prdata),
      .pslverr        (pslverr),

      .ctrl_offset    (regs_2_ctrl_ctrl_offset),
      .ctrl_size      (regs_2_ctrl_ctrl_size),
      .ctrl_clr       (regs_2_rx_ctrl_ctrl_clr),

      .status_cnt_drop(rx_ctrl_2_regs_status_cnt_drop),
      .status_rx_lvl  (rx_fifo_2_regs_fifo_lvl),
      .status_tx_lvl  (tx_fifo_2_regs_fifo_lvl),

      .rx_fifo_empty  (rx_fifo_2_regs_fifo_empty),
      .rx_fifo_full   (rx_fifo_2_regs_fifo_full),
      .tx_fifo_empty  (tx_fifo_2_regs_fifo_empty),
      .tx_fifo_full   (tx_fifo_2_regs_fifo_full),
      .max_drop       (rx_ctrl_2_regs_status_cnt_drop == (('h1 << STATUS_CNT_DROP_WIDTH) - 1)),
      
      .irq            (irq)
    );
  endmodule

`endif