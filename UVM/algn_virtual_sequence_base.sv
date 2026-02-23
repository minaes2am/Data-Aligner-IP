`ifndef ALGN_VIRTUAL_SEQUENCE_BASE_SV
  `define ALGN_VIRTUAL_SEQUENCE_BASE_SV

  `include "uvm_macros.svh"
  `include "algn_virtual_sequencer.sv"
  
   import uvm_pkg::*;
 
  class algn_virtual_sequence_base extends uvm_sequence;
    
    `uvm_declare_p_sequencer(algn_virtual_sequencer)

    `uvm_object_utils(algn_virtual_sequence_base)
    
    function new(string name = "algn_virtual_sequence_base");
      super.new(name);
    endfunction
    
  endclass

`endif
    
