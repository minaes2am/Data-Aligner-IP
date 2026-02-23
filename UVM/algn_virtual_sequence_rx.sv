`ifndef ALGN_VIRTUAL_SEQUENCE_RX_SV
  `define ALGN_VIRTUAL_SEQUENCE_RX_SV

  `include "uvm_macros.svh"
  `include "algn_virtual_sequence_base.sv"
  
   import uvm_pkg::*; 

  class algn_virtual_sequence_rx extends algn_virtual_sequence_base;
    
    //Sequence for sending one MD RX transaction
    rand md_sequence_simple_master seq;
    
    `uvm_object_utils(algn_virtual_sequence_rx)
    
    function new(string name = "algn_virtual_sequence_rx");
      super.new(name);
      
      seq = md_sequence_simple_master::type_id::create("seq");
    endfunction
    
    function void pre_randomize();
      super.pre_randomize();
      
      seq.set_sequencer(p_sequencer.md_rx_sequencer);
    endfunction
    
    virtual task body();
      seq.start(p_sequencer.md_rx_sequencer);
    endtask

  endclass

`endif
