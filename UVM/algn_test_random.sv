`ifndef ALGN_TEST_RANDOM_SV
  `define ALGN_TEST_RANDOM_SV

   `include "uvm_macros.svh"
   `include "algn_test_base.sv"
   `include "algn_virtual_sequence_reg_config.sv"
   `include "algn_virtual_sequence_rx.sv"
   `include "algn_virtual_sequence_reg_status.sv"
  
    import uvm_pkg::*;
    import md_pkg::*;
    import apb_pkg::*;

  class algn_test_random extends algn_test_base;
    
    //Number of MD RX transactions sent per CTRL configuration
    protected int unsigned num_md_rx_transactions;

    // Number of CTRL configurations to cycle through.
    // For a 32-bit design there are 6 valid (offset, size) pairs, so 12
    // repetitions guarantees every pair is visited at least twice via the
    // round-robin selector in algn_virtual_sequence_reg_config.
    protected int unsigned num_cfg_repetitions;

    `uvm_component_utils(algn_test_random)
    
    function new(string name = "algn_test_random", uvm_component parent);
      super.new(name, parent);
      
      num_md_rx_transactions = 100;
      num_cfg_repetitions    = 12;
    endfunction

    // -----------------------------------------------------------------------
    // drain_tx_pipeline
    //
    // Waits until every TX item the model has predicted has been consumed by
    // the TX slave (model.is_tx_drained() == 1, i.e. tx_pending == 0).
    //
    // MUST be called with scoreboard.drain_mode=1 active so that incoming DUT
    // TX outputs are silently discarded without touching exp_tx_items (which
    // was just flushed and must remain empty until the new batch starts).
    //
    // Uses the uncapped tx_pending counter (not tx_lvl which is capped at
    // FIFO_DEPTH=8) so it stays accurate even when a single RX burst generates
    // more than 8 TX predictions.
    //
    // A hard timeout of MAX_DRAIN_CYCLES guards against permanent stalls.
    // -----------------------------------------------------------------------
    protected virtual task drain_tx_pipeline();
      localparam int unsigned MAX_DRAIN_CYCLES = 50000;
      algn_vif vif = env.env_config.get_vif();
      int unsigned waited = 0;
      
      while(!env.virtual_sequencer.model.is_tx_drained()) begin
        @(posedge vif.clk);
        waited++;
        if(waited >= MAX_DRAIN_CYCLES) begin
          `uvm_error("DRAIN_TIMEOUT",
            $sformatf("drain_tx_pipeline: still %0d TX items pending after %0d cycles. Forcing continue.",
                      env.virtual_sequencer.model.get_tx_pending(), MAX_DRAIN_CYCLES))
          break;
        end
      end
      // Extra settling: let the last ITEM_END propagate through all analysis ports
      // before we turn drain_mode off and start comparing new traffic.
      repeat(50) @(posedge vif.clk);
    endtask
     
    virtual task run_phase(uvm_phase phase); 
      uvm_status_e status;
      
      phase.raise_objection(this, "TEST_DONE");
       
      #(100ns);
       
      fork
        begin
          // TX slave: cycle through driver length 0..9 (round-robin) so that
          // the TX monitor sees length values 1..10, covering all coverage bins.
          md_sequence_simple_slave seq;
          md_item_mon item_mon;
          int unsigned len_rr = 0;
          forever begin
            env.virtual_sequencer.md_tx_sequencer.pending_items.get(item_mon);
            seq = md_sequence_simple_slave::type_id::create("seq");
            void'(seq.randomize() with {
              seq.item.length == (len_rr % 10);
            });
            seq.start(env.virtual_sequencer.md_tx_sequencer);
            len_rr++;
          end
        end
      join_none
      
      repeat(num_cfg_repetitions) begin

        // ---- 1. Enter drain mode -------------------------------------------
        //
        // drain_mode=1 makes write_in_agent_tx silently discard all incoming
        // DUT TX items WITHOUT touching exp_tx_items.  This is critical: after
        // flush (step 2), exp_tx_items is empty and must stay empty until the
        // new batch starts producing fresh predictions.  Without drain_mode, any
        // residual DUT TX output during the drain window would trigger a
        // "no expected entry" error.
        env.virtual_sequencer.scoreboard.set_drain_mode(1);
        env.env_config.set_has_checks(0);

        // ---- 2. Flush stale model and scoreboard state ---------------------
        //
        // Discard partial bytes accumulated under the old CTRL (partial_buf /
        // byte_buf) and all pending expected TX items from the old batch.
        // algn_virtual_sequence_reg_config (step 5) flushes again as a safety
        // net; those extra calls are harmless no-ops on already-empty queues.
        env.virtual_sequencer.model.flush_partial_buf();
        env.virtual_sequencer.scoreboard.flush_tx_queue();

        // ---- 3. Drain: wait for ALL predicted TX items to be consumed -----
        //
        // Polls model.is_tx_drained() (tx_pending==0) rather than using a fixed
        // cycle count.  tx_pending is an uncapped counter that correctly tracks
        // all predictions, unlike tx_lvl which saturates at FIFO_DEPTH.
        // All DUT TX outputs during this window are silently discarded
        // (drain_mode=1) and tx_pending decrements on each TX ITEM_END.
        drain_tx_pipeline();

        // ---- 4. Write new CTRL configuration ------------------------------
        //
        // drain_mode stays ON during the entire reg_config sequence.
        // Between the first flush (step 2) and the actual CTRL write, several
        // APB transactions occur (IRQEN, STATUS, other RW regs).  During those
        // clock cycles RX items can still arrive; the model would process them
        // under the OLD ctrl_size and add stale predictions to exp_tx_items.
        // Keeping drain_mode=1 here means write_in_agent_tx silently discards
        // residual DUT TX output without touching exp_tx_items.
        // algn_virtual_sequence_reg_config flushes again internally (before and
        // after the CTRL write) to clear any such stale predictions.
        begin
          algn_virtual_sequence_reg_config seq = algn_virtual_sequence_reg_config::type_id::create("seq");
          seq.set_sequencer(env.virtual_sequencer);
          void'(seq.randomize());
          seq.start(env.virtual_sequencer);
        end

        // ---- 5. Exit drain mode and re-enable checks ----------------------
        //
        // CTRL is now written and both model and scoreboard queues are clean
        // (flushed inside reg_config after the CTRL write).  It is now safe to
        // exit drain mode and start comparing new TX traffic against fresh
        // predictions made under the new ctrl config.
        env.virtual_sequencer.scoreboard.set_drain_mode(0);
        env.env_config.set_has_checks(1);

        // ---- 6. Send RX batch for this CTRL config ------------------------
        repeat(num_md_rx_transactions) begin
          algn_virtual_sequence_rx seq = algn_virtual_sequence_rx::type_id::create("seq");
          seq.set_sequencer(env.virtual_sequencer);
          void'(seq.randomize());
          seq.start(env.virtual_sequencer);
        end

        // ---- 7. Read STATUS registers -------------------------------------
        begin
          algn_virtual_sequence_reg_status seq = algn_virtual_sequence_reg_status::type_id::create("seq");
          void'(seq.randomize());
          seq.start(env.virtual_sequencer);
        end
      end

      // ---- Final drain: let last batch complete before ending test --------
      env.virtual_sequencer.scoreboard.set_drain_mode(1);
      env.env_config.set_has_checks(0);
      env.virtual_sequencer.model.flush_partial_buf();
      env.virtual_sequencer.scoreboard.flush_tx_queue();
      drain_tx_pipeline();
      env.virtual_sequencer.scoreboard.set_drain_mode(0);
      env.env_config.set_has_checks(1);
      
      #(500ns);
      
      phase.drop_objection(this, "TEST_DONE"); 
    endtask
    
  endclass

`endif