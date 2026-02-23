`ifndef ALGN_SPLIT_INFO_SV
  `define ALGN_SPLIT_INFO_SV
 
   `include "uvm_macros.svh"
   import uvm_pkg::*;

  class algn_split_info extends uvm_object;
    
    //Value of CTRL.OFFSET
    int unsigned ctrl_offset;
    
    //Value of CTRL.SIZE
    int unsigned ctrl_size;
    
    //Value of the MD transaction offset
    int unsigned md_offset;
    
    //Value of the MD transaction size
    int unsigned md_size;
    
    //Number of bytes needed during the split
    int unsigned num_bytes_needed;
    
    `uvm_object_utils(algn_split_info)
    
    function new(string name = "algn_split_info");
      super.new(name);
    endfunction
    
  endclass

`endif
    
