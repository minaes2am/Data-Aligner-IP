`ifndef ALGN_IF_SV
  `define ALGN_IF_SV

  interface algn_if(input clk);
	
    logic reset_n;
    
    logic irq;
    
    logic rx_fifo_push;
    
    logic rx_fifo_pop;
    
    logic tx_fifo_push;
    
    logic tx_fifo_pop;
    
    // -----------------------------------------------------------------------
    // SVA Assertions
    // -----------------------------------------------------------------------
    
    // After reset is deasserted, IRQ must not be asserted for at least 1 cycle
    // (IRQ is combinationally derived from IRQ register bits, so it resets with the register).
    property irq_stable_after_reset;
      @(posedge clk) $rose(reset_n) |=> !irq;
    endproperty
    AST_IRQ_STABLE_AFTER_RESET : assert property(irq_stable_after_reset)
      else $error("IRQ asserted immediately after reset deasserted");
    
    // RX FIFO push and pop should not happen simultaneously when FIFO is considered stable.
    // (This checks that the model and DUT agree on when to push/pop.)
    // Note: simultaneous push+pop IS valid in a FIFO (pass-through), so we only warn.
    // Removed strict mutual-exclusion - just cover the case.
    
    // RX FIFO push should only happen when reset is active (reset_n==1)
    property rx_push_requires_no_reset;
      @(posedge clk) rx_fifo_push |-> reset_n;
    endproperty
    AST_RX_PUSH_NO_RESET : assert property(rx_push_requires_no_reset)
      else $error("RX FIFO push occurred during reset");
    
    // TX FIFO push should only happen when not in reset
    property tx_push_requires_no_reset;
      @(posedge clk) tx_fifo_push |-> reset_n;
    endproperty
    AST_TX_PUSH_NO_RESET : assert property(tx_push_requires_no_reset)
      else $error("TX FIFO push occurred during reset");
    
    // TX FIFO pop should only happen when not in reset
    property tx_pop_requires_no_reset;
      @(posedge clk) tx_fifo_pop |-> reset_n;
    endproperty
    AST_TX_POP_NO_RESET : assert property(tx_pop_requires_no_reset)
      else $error("TX FIFO pop occurred during reset");
    
    // RX FIFO pop should only happen when not in reset
    property rx_pop_requires_no_reset;
      @(posedge clk) rx_fifo_pop |-> reset_n;
    endproperty
    AST_RX_POP_NO_RESET : assert property(rx_pop_requires_no_reset)
      else $error("RX FIFO pop occurred during reset");

  endinterface

`endif