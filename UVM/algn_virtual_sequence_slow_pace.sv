`ifndef ALGN_VIRTUAL_SEQUENCE_SLOW_PACE_SV
  `define ALGN_VIRTUAL_SEQUENCE_SLOW_PACE_SV

  `include "uvm_macros.svh"
  `include "algn_virtual_sequence_base.sv"
  
   import uvm_pkg::*;
   import md_pkg::*;
  
  class algn_virtual_sequence_slow_pace extends algn_virtual_sequence_base;
     
    `uvm_object_utils(algn_virtual_sequence_slow_pace)
    
    function new(string name = "algn_virtual_sequence_slow_pace");
      super.new(name);
    endfunction
    
    virtual task body();
      md_sequence_simple_master rx_sequence;
      
      fork
        begin
          int unsigned algn_data_width = p_sequencer.model.env_config.get_algn_data_width();
          int unsigned ctrl_size       = p_sequencer.model.reg_block.CTRL.SIZE.get_mirrored_value();
          
          `uvm_do_on_with(rx_sequence, p_sequencer.md_rx_sequencer, {
            ((algn_data_width / 8) + item.offset) % item.data.size() == 0;
            (item.data.size() + item.offset)                         <= (algn_data_width / 8);
            
            item.data.size() >= ctrl_size;
          })
        end
        begin
          int unsigned tx_item_idx = 0;
          int unsigned num_tx_items;
          
          do begin
            md_sequence_simple_slave tx_sequence;
            md_item_mon item_mon;

            p_sequencer.md_tx_sequencer.pending_items.get(item_mon);
            
            num_tx_items = rx_sequence.item.data.size() / p_sequencer.model.reg_block.CTRL.SIZE.get_mirrored_value();

            `uvm_do_on_with(tx_sequence, p_sequencer.md_tx_sequencer, {
              num_tx_items == 1                                     -> item.response == MD_OKAY;
              num_tx_items > 1 && tx_item_idx <  (num_tx_items - 1) -> item.response == MD_OKAY;
              num_tx_items > 1 && tx_item_idx == (num_tx_items - 1) -> item.response == MD_ERR;
            })
            
            tx_item_idx++;
          end while(tx_item_idx < num_tx_items);
        end
      join
      
    endtask

  endclass

`endif
    

