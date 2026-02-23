`ifndef ALGN_VIRTUAL_SEQUENCE_REG_CONFIG_SV
  `define ALGN_VIRTUAL_SEQUENCE_REG_CONFIG_SV

  `include "uvm_macros.svh"
  `include "algn_virtual_sequence_base.sv"
  
   import uvm_pkg::*; 
  
  class algn_virtual_sequence_reg_config extends algn_virtual_sequence_base;
    
    `uvm_object_utils(algn_virtual_sequence_reg_config)
    
    function new(string name = "algn_virtual_sequence_reg_config");
      super.new(name);
    endfunction
    
    virtual task body();
      uvm_reg registers[$];
      uvm_status_e status;
      
      p_sequencer.model.reg_block.get_registers(registers);
      
      for(int reg_idx = registers.size() - 1; reg_idx >= 0; reg_idx--) begin
       if(!(registers[reg_idx].get_rights() inside {"RW", "WO"})) begin
        registers.delete(reg_idx);
       end
       else if(registers[reg_idx].get_name() == "IRQ") begin
        registers.delete(reg_idx);
        end
      end
      
      registers.shuffle();
      
      foreach(registers[reg_idx]) begin
        void'(registers[reg_idx].randomize());
        
        registers[reg_idx].write(status, registers[reg_idx].get());
      end 
    endtask
    
  endclass

`endif
