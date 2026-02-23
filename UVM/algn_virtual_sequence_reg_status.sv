`ifndef ALGN_VIRTUAL_SEQUENCE_REG_STATUS_SV
  `define ALGN_VIRTUAL_SEQUENCE_REG_STATUS_SV

   `include "uvm_macros.svh"
  `include "algn_virtual_sequence_base.sv"
  
   import uvm_pkg::*; 
  
  class algn_virtual_sequence_reg_status extends algn_virtual_sequence_base;
    
    `uvm_object_utils(algn_virtual_sequence_reg_status)
    
    function new(string name = "algn_virtual_sequence_reg_status");
      super.new(name);
    endfunction
    
    virtual task body();
      uvm_reg registers[$];
      uvm_status_e status;
      uvm_reg_data_t data;
      
      p_sequencer.model.reg_block.get_registers(registers);
      
      for(int reg_idx = registers.size() - 1; reg_idx >= 0; reg_idx--) begin
        if(!(registers[reg_idx].get_rights() inside {"RO"})) begin
          registers.delete(reg_idx);
        end
      end
      
      registers.shuffle();
      
      foreach(registers[reg_idx]) begin
        registers[reg_idx].read(status, data);
      end 
    endtask
    
  endclass

`endif
