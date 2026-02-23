`ifndef ALGN_SEQ_REG_CONFIG_SV
  `define ALGN_SEQ_REG_CONFIG_SV

  `include "uvm_macros.svh"

   import uvm_pkg::*;
   import algn_reg_pkg::*;

  class algn_seq_reg_config extends uvm_reg_sequence;
    
    algn_reg_block reg_block;

    `uvm_object_utils(algn_seq_reg_config)
    
    function new(string name = "algn_seq_reg_config");
      super.new(name);
    endfunction
    
    virtual task body();
      uvm_status_e status;
      uvm_reg_data_t data;
      
      void'(reg_block.CTRL.randomize());
      
      reg_block.CTRL.write(status, reg_block.CTRL.get());
      
      reg_block.CTRL.read(status, data);
      
    endtask
    
  endclass

`endif
