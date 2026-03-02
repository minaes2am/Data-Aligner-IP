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
      
      // Build a list of all valid (offset, size) pairs for this data width,
      // applying the same two DUT validity checks that regs.sv enforces:
      //   1. (dw_bytes + offset) % size == 0
      //   2. offset + size <= dw_bytes
      // Then pick one via round-robin so repeated calls sweep all valid pairs.
      begin
        typedef struct { int unsigned offset; int unsigned size; } ctrl_pair_t;
        ctrl_pair_t valid_pairs[$];
        ctrl_pair_t chosen;
        static int unsigned rr_index = 0;
        
        int unsigned dw_bytes = reg_block.CTRL.GET_ALGN_DATA_WIDTH() / 8;
        
        for(int unsigned off = 0; off < dw_bytes; off++) begin
          for(int unsigned sz = 1; sz <= dw_bytes; sz++) begin
            if(((dw_bytes + off) % sz) != 0) continue;
            if(off + sz > dw_bytes) continue;
            begin
              ctrl_pair_t p;
              p.offset = off;
              p.size   = sz;
              valid_pairs.push_back(p);
            end
          end
        end
        
        if(valid_pairs.size() > 0) begin
          chosen = valid_pairs[rr_index % valid_pairs.size()];
          rr_index++;
        end else begin
          chosen.offset = 0;
          chosen.size   = 1;
        end
        
        void'(reg_block.CTRL.SIZE.set(chosen.size));
        void'(reg_block.CTRL.OFFSET.set(chosen.offset));
        void'(reg_block.CTRL.CLR.set(0));
      end
      
      reg_block.CTRL.write(status, reg_block.CTRL.get());
      
      reg_block.CTRL.read(status, data);
      
    endtask
    
  endclass

`endif