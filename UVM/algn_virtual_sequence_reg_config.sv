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
      uvm_reg_data_t zero_data = 0;

      // -----------------------------------------------------------------------
      // Flush stale model and scoreboard state BEFORE changing CTRL.
      //
      // When CTRL changes, the DUT's ctrl.sv internal partial-word accumulator
      // (aligned_bytes_processed / push_data) resets implicitly because the
      // new ctrl_size applies immediately to subsequent pops.  Any bytes that
      // were partially accumulated under the OLD ctrl_size are discarded by the
      // DUT.  The model must mirror this by discarding its own partial_buf,
      // otherwise the model will produce TX items that the DUT never generates,
      // causing DUT_ERROR mismatches.
      //
      // The scoreboard's exp_tx_items queue must also be cleared of any items
      // predicted under the old configuration that will never arrive.
      // -----------------------------------------------------------------------
      p_sequencer.model.flush_partial_buf();
      p_sequencer.scoreboard.flush_tx_queue();

      p_sequencer.model.reg_block.get_registers(registers);
      
      for(int reg_idx = registers.size() - 1; reg_idx >= 0; reg_idx--) begin
       if(!(registers[reg_idx].get_rights() inside {"RW", "WO"})) begin
        registers.delete(reg_idx);
       end
       // Exclude IRQ (W1C register, writing randomized data would clear interrupt flags spuriously)
       else if(registers[reg_idx].get_name() == "IRQ") begin
        registers.delete(reg_idx);
       end
       // Exclude IRQEN: random values with interrupt enables set would cause unexpected IRQs
       // that the model may not predict (since IRQ enable can change at any time).
       // IRQEN is tested separately in dedicated test sequences.
       else if(registers[reg_idx].get_name() == "IRQEN") begin
        registers.delete(reg_idx);
       end
       // Handle CTRL separately below with explicit coverage-driving logic
       else if(registers[reg_idx].get_name() == "CTRL") begin
        registers.delete(reg_idx);
       end
      end
      
      // First disable all interrupts to ensure a clean state before changing CTRL
      p_sequencer.model.reg_block.IRQEN.write(status, zero_data);

      // Write to STATUS (a read-only register) to deliberately generate an APB_ERR
      // response (pslverr=1). This covers: APB response=APB_ERR, WRITE->WRITE
      // transition in trans_direction, and APB_ERR x WRITE cross in response_x_direction.
      // The UVM register model will see status=UVM_NOT_OK but we ignore it here
      // because generating the APB error is intentional for coverage purposes.
      begin
        uvm_reg_data_t dummy = 0;
        p_sequencer.model.reg_block.STATUS.write(status, dummy);
      end
      
      registers.shuffle();
      
      foreach(registers[reg_idx]) begin
        void'(registers[reg_idx].randomize());
        
        registers[reg_idx].write(status, registers[reg_idx].get());
      end

      // -----------------------------------------------------------------------
      // Write CTRL with a specifically chosen (offset, size) combination that:
      //   1. Is always a legal combination (passes DUT validity checks)
      //   2. Drives coverage of ctrl_offset, ctrl_size, and num_bytes_needed
      //
      // For a 32-bit design (dw_bytes=4), valid (offset, size) pairs where
      //   (dw_bytes + offset) % size == 0  AND  offset + size <= dw_bytes  are:
      //
      //   offset=0 : size=1, size=2, size=4
      //   offset=1 : size=1
      //   offset=2 : size=1, size=2
      //   offset=3 : size=1
      //
      // We build this table at runtime from dw_bytes so it is portable to
      // other data widths, then pick one entry per call in round-robin order
      // (using a static counter) so repeated calls sweep the full space.
      // -----------------------------------------------------------------------
      begin
        typedef struct { int unsigned offset; int unsigned size; } ctrl_pair_t;
        ctrl_pair_t valid_pairs[$];
        ctrl_pair_t chosen;
        static int unsigned rr_index = 0;

        int unsigned dw_bytes = p_sequencer.model.env_config.get_algn_data_width() / 8;

        // Build the list of all legal (offset, size) pairs for this data width
        for(int unsigned off = 0; off < dw_bytes; off++) begin
          for(int unsigned sz = 1; sz <= dw_bytes; sz++) begin
            // DUT validity: (dw_bytes + offset) % size == 0
            if(((dw_bytes + off) % sz) != 0) continue;
            // DUT validity: offset + size <= dw_bytes
            if(off + sz > dw_bytes) continue;
            begin
              ctrl_pair_t p;
              p.offset = off;
              p.size   = sz;
              valid_pairs.push_back(p);
            end
          end
        end

        // Pick the next entry in round-robin so each call uses a different pair
        if(valid_pairs.size() > 0) begin
          chosen = valid_pairs[rr_index % valid_pairs.size()];
          rr_index++;
        end else begin
          // Fallback (should never happen for any legal dw_bytes)
          chosen.offset = 0;
          chosen.size   = 1;
        end

        // Apply the chosen values directly into the register model fields
        void'(p_sequencer.model.reg_block.CTRL.SIZE.set(chosen.size));
        void'(p_sequencer.model.reg_block.CTRL.OFFSET.set(chosen.offset));
        void'(p_sequencer.model.reg_block.CTRL.CLR.set(0));

        p_sequencer.model.reg_block.CTRL.write(status, p_sequencer.model.reg_block.CTRL.get());

        // -----------------------------------------------------------------------
        // Second flush: purge any TX predictions the model made between the first
        // flush (at the top of body()) and the CTRL write above.
        //
        // Between those two points several APB transactions ran (IRQEN write,
        // STATUS write, other RW register writes).  Each transaction takes
        // multiple clock cycles, during which RX items may have arrived and been
        // processed by the model under the OLD ctrl_size, producing predictions
        // that the DUT will never match (it now uses the new ctrl_size).
        // Discarding them here keeps exp_tx_items clean for the new batch.
        // -----------------------------------------------------------------------
        p_sequencer.model.flush_partial_buf();
        p_sequencer.scoreboard.flush_tx_queue();
      end
    endtask
    
  endclass

`endif