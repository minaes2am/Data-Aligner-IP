`ifndef ALGN_TEST_RANDOM_RX_ERR_SV
  `define ALGN_TEST_RANDOM_RX_ERR_SV

  `include "uvm_macros.svh"
  `include "algn_test_random.sv"
  `include "algn_virtual_sequence_rx_err.sv"
  import uvm_pkg::*;

  class algn_test_random_rx_err extends algn_test_random;
    
    `uvm_component_utils(algn_test_random_rx_err)
    
    function new(string name = "algn_test_random_rx_err", uvm_component parent);
      super.new(name, parent);
      
      num_md_rx_transactions = 300;
      
      algn_virtual_sequence_rx::type_id::set_type_override(algn_virtual_sequence_rx_err::get_type());
    endfunction
     
  endclass
 
`endif  
