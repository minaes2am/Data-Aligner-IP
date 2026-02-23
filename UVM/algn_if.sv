`ifndef ALGN_IF_SV
  `define ALGN_IF_SV

  interface algn_if(input clk);
	
    logic reset_n;
    
    logic irq;
    
    logic rx_fifo_push;
    
    logic rx_fifo_pop;
    
    logic tx_fifo_push;
    
    logic tx_fifo_pop;
    
  endinterface

`endif
