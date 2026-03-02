`ifndef ALGN_MODEL_SV
  `define ALGN_MODEL_SV

  `include "uvm_macros.svh"
  `include "algn_env_config.sv"
  `include "algn_split_info.sv"
  `include "algn_clr_cnt_drop.sv"

  import uvm_pkg::*;
  import md_pkg::*;
  import apb_pkg::*;
  import uvm_ext_pkg::*;
  import algn_reg_pkg::*;

  `uvm_analysis_imp_decl(_in_rx)
  `uvm_analysis_imp_decl(_in_tx)

  // One entry in the byte buffer: the raw byte plus source item metadata
  // needed to populate algn_split_info for coverage.
  typedef struct {
    byte unsigned val;
    int unsigned  md_offset;
    int unsigned  md_size;
  } algn_byte_entry;

  class algn_model extends uvm_component implements uvm_ext_reset_handler;

    algn_env_config  env_config;
    algn_reg_block   reg_block;

    uvm_analysis_imp_in_rx#(md_item_mon, algn_model) port_in_rx;
    uvm_analysis_imp_in_tx#(md_item_mon, algn_model) port_in_tx;
    uvm_analysis_port#(md_response)     port_out_rx;
    uvm_analysis_port#(md_item_mon)     port_out_tx;
    uvm_analysis_port#(bit)             port_out_irq;
    uvm_analysis_port#(algn_split_info) port_out_split_info;

    // -----------------------------------------------------------------------
    // Internal state
    // -----------------------------------------------------------------------

    // Flat byte buffer: holds payload bytes from accepted RX items in arrival
    // order, tagged with their source item's offset/size for split coverage.
    protected algn_byte_entry byte_buf[$];

    // Bytes already accumulated into the current (partial) output word.
    // When this reaches ctrl_size, we emit one TX item and reset.
    protected algn_byte_entry partial_buf[$];

    // IRQ pending flag set by helpers, consumed by send_exp_irq_task.
    protected bit exp_irq;

    // Mirrored FIFO levels for STATUS register prediction.
    protected int unsigned rx_lvl;
    protected int unsigned tx_lvl;
    localparam int unsigned FIFO_DEPTH = 8;

    // Uncapped count of TX predictions outstanding (port_out_tx.write calls not yet
    // matched by a TX ITEM_END). Unlike tx_lvl (capped at FIFO_DEPTH for STATUS
    // accuracy), this is exact and is used by is_tx_drained() for drain detection.
    protected int unsigned tx_pending;

    // Process handle for background IRQ task.
    local process proc_irq;

    `uvm_component_utils(algn_model)

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      port_in_rx          = new("port_in_rx",          this);
      port_in_tx          = new("port_in_tx",          this);
      port_out_rx         = new("port_out_rx",         this);
      port_out_tx         = new("port_out_tx",         this);
      port_out_irq        = new("port_out_irq",        this);
      port_out_split_info = new("port_out_split_info", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(reg_block == null) begin
        reg_block = algn_reg_block::type_id::create("reg_block", this);
        reg_block.build();
        reg_block.lock_model();
      end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      algn_clr_cnt_drop cbs = algn_clr_cnt_drop::type_id::create("cbs", this);
      super.connect_phase(phase);
      cbs.cnt_drop = reg_block.STATUS.CNT_DROP;
      uvm_callbacks#(uvm_reg_field, algn_clr_cnt_drop)::add(reg_block.CTRL.CLR, cbs);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      reg_block.CTRL.SET_ALGN_DATA_WIDTH(env_config.get_algn_data_width());
    endfunction

    virtual task run_phase(uvm_phase phase);
      fork
        send_exp_irq_task();
      join_none
    endtask

    // -----------------------------------------------------------------------
    // Reset
    // -----------------------------------------------------------------------
    virtual function void handle_reset(uvm_phase phase);
      reg_block.reset("HARD");
      if(proc_irq      != null) begin proc_irq.kill();      proc_irq      = null; end
      byte_buf.delete();
      partial_buf.delete();
      exp_irq = 0;
      rx_lvl  = 0;
      tx_lvl  = 0;
      tx_pending = 0;
      fork
        send_exp_irq_task();
      join_none
    endfunction

    virtual function bit is_empty();
      return (byte_buf.size() == 0) && (partial_buf.size() == 0);
    endfunction

    // Returns the uncapped number of TX predictions still awaiting a DUT ITEM_END.
    // Accurate even when tx_lvl is saturated at FIFO_DEPTH.
    virtual function int unsigned get_tx_pending();
      return tx_pending;
    endfunction

    // Returns 1 when ALL predicted TX items have been consumed by the TX slave.
    // Uses the uncapped tx_pending counter (not tx_lvl) to avoid false early exits
    // when a burst pushes more than FIFO_DEPTH items into the queue.
    virtual function bit is_tx_drained();
      return (tx_pending == 0);
    endfunction

    // -----------------------------------------------------------------------
    // flush_partial_buf
    //
    // Called by algn_virtual_sequence_reg_config before writing a new CTRL
    // value.  The DUT's ctrl.sv does not have an explicit pipeline-clear input
    // (CLR only resets cnt_drop in rx_ctrl).  When CTRL.SIZE or CTRL.OFFSET
    // changes, ctrl.sv begins applying the new values immediately on the next
    // pop from the RX FIFO; any partially accumulated aligned word built under
    // the old ctrl_size is simply discarded (the push_data register holds
    // whatever partial bytes were accumulated, but push_valid stays 0 so
    // nothing is written to the TX FIFO).
    //
    // The model must mirror this: discard partial_buf and byte_buf so that no
    // TX items are predicted from data that was accepted under the old config
    // but not yet assembled into a full aligned word.
    // -----------------------------------------------------------------------
    virtual function void flush_partial_buf();
      int unsigned nb = partial_buf.size();
      int unsigned bb = byte_buf.size();
      partial_buf.delete();
      byte_buf.delete();
      if(nb > 0 || bb > 0)
        `uvm_info("MODEL_FLUSH",
          $sformatf("flush_partial_buf: discarded %0d partial bytes and %0d buffered bytes on CTRL change",
                    nb, bb), UVM_MEDIUM)
    endfunction

    // -----------------------------------------------------------------------
    // RX error prediction — exact mirror of rx_ctrl.sv combinational logic
    // -----------------------------------------------------------------------
    protected virtual function md_response get_exp_response(md_item_mon item);
      int unsigned dw_bytes = env_config.get_algn_data_width() / 8;
      if(item.data.size() == 0) return MD_ERR;
      if(((dw_bytes + item.offset) % item.data.size()) != 0) return MD_ERR;
      return MD_OKAY;
    endfunction

    // -----------------------------------------------------------------------
    // STATUS / IRQ helpers
    // -----------------------------------------------------------------------
    protected virtual function void set_max_drop();
      void'(reg_block.IRQ.MAX_DROP.predict(1));
      if(reg_block.IRQEN.MAX_DROP.get_mirrored_value() == 1) exp_irq = 1;
    endfunction

    protected virtual function void inc_cnt_drop(md_response response);
      uvm_reg_data_t max_val = ('h1 << reg_block.STATUS.CNT_DROP.get_n_bits()) - 1;
      if(reg_block.STATUS.CNT_DROP.get_mirrored_value() < max_val) begin
        void'(reg_block.STATUS.CNT_DROP.predict(
              reg_block.STATUS.CNT_DROP.get_mirrored_value() + 1));
        `uvm_info("CNT_DROP", $sformatf("CNT_DROP=%0d (%0s)",
                  reg_block.STATUS.CNT_DROP.get_mirrored_value(), response.name()), UVM_LOW)
        if(reg_block.STATUS.CNT_DROP.get_mirrored_value() == max_val)
          set_max_drop();
      end
    endfunction

    protected virtual function void do_rx_lvl_up();
      rx_lvl++;
      void'(reg_block.STATUS.RX_LVL.predict(rx_lvl));
      if(rx_lvl == FIFO_DEPTH) begin
        void'(reg_block.IRQ.RX_FIFO_FULL.predict(1));
        if(reg_block.IRQEN.RX_FIFO_FULL.get_mirrored_value() == 1) exp_irq = 1;
        `uvm_info("RX_FIFO", $sformatf("RX FIFO full - IRQEN.RX_FIFO_FULL:%0d",
                  reg_block.IRQEN.RX_FIFO_FULL.get_mirrored_value()), UVM_MEDIUM)
      end
    endfunction

    protected virtual function void do_rx_lvl_down();
      if(rx_lvl == 0) return;
      rx_lvl--;
      void'(reg_block.STATUS.RX_LVL.predict(rx_lvl));
      if(rx_lvl == 0) begin
        void'(reg_block.IRQ.RX_FIFO_EMPTY.predict(1));
        if(reg_block.IRQEN.RX_FIFO_EMPTY.get_mirrored_value() == 1) exp_irq = 1;
        `uvm_info("RX_FIFO", $sformatf("RX FIFO empty - IRQEN.RX_FIFO_EMPTY:%0d",
                  reg_block.IRQEN.RX_FIFO_EMPTY.get_mirrored_value()), UVM_MEDIUM)
      end
    endfunction

    protected virtual function void do_tx_lvl_up();
      // Cap at FIFO_DEPTH: the model emits predictions immediately without
      // back-pressure, so tx_lvl may exceed the physical FIFO depth.
      // Only increment and signal IRQ up to FIFO_DEPTH to match DUT behavior.
      if(tx_lvl < FIFO_DEPTH) begin
        tx_lvl++;
        void'(reg_block.STATUS.TX_LVL.predict(tx_lvl));
        if(tx_lvl == FIFO_DEPTH) begin
          void'(reg_block.IRQ.TX_FIFO_FULL.predict(1));
          if(reg_block.IRQEN.TX_FIFO_FULL.get_mirrored_value() == 1) exp_irq = 1;
          `uvm_info("TX_FIFO", $sformatf("TX FIFO full - IRQEN.TX_FIFO_FULL:%0d",
                    reg_block.IRQEN.TX_FIFO_FULL.get_mirrored_value()), UVM_MEDIUM)
        end
      end
    endfunction

    protected virtual function void do_tx_lvl_down();
      if(tx_lvl == 0) return;
      tx_lvl--;
      void'(reg_block.STATUS.TX_LVL.predict(tx_lvl));
      if(tx_lvl == 0) begin
        void'(reg_block.IRQ.TX_FIFO_EMPTY.predict(1));
        if(reg_block.IRQEN.TX_FIFO_EMPTY.get_mirrored_value() == 1) exp_irq = 1;
        `uvm_info("TX_FIFO", $sformatf("TX FIFO empty - IRQEN.TX_FIFO_EMPTY:%0d",
                  reg_block.IRQEN.TX_FIFO_EMPTY.get_mirrored_value()), UVM_MEDIUM)
      end
    endfunction

    // -----------------------------------------------------------------------
    // run_align()
    //
    // Called every time new bytes arrive in byte_buf (from write_in_rx).
    // Mirrors ctrl.sv byte-level logic:
    //   - partial_buf accumulates bytes towards the current ctrl_size word
    //   - when partial_buf.size() == ctrl_size, emit one TX item and reset
    //   - repeat until byte_buf is exhausted
    //
    // A "split" occurs when partial_buf is non-empty at the start of a new
    // output word (bytes from two different RX items contribute to one word).
    // -----------------------------------------------------------------------
    protected virtual function void run_align();
      forever begin
        int unsigned ctrl_size   = reg_block.CTRL.SIZE.get_mirrored_value();
        int unsigned ctrl_offset = reg_block.CTRL.OFFSET.get_mirrored_value();
        int unsigned bytes_needed;

        if(ctrl_size == 0) return;

        bytes_needed = ctrl_size - partial_buf.size();

        // Not enough bytes in the buffer to complete the next output word
        if(byte_buf.size() < bytes_needed) begin
          // Move whatever bytes are in byte_buf into partial_buf to carry over
          while(byte_buf.size() > 0) begin
            partial_buf.push_back(byte_buf.pop_front());
          end
          return;
        end

        // ---- We have enough bytes to complete one output word ----
        begin
          bit          is_split;
          md_item_mon  tx_item;
          int unsigned split_md_offset;
          int unsigned split_md_size;
          int unsigned split_num_bytes;

          // A split occurred if partial_buf already had bytes in it
          is_split        = (partial_buf.size() > 0);
          split_num_bytes = bytes_needed;

          // Capture metadata for split coverage from the first new byte
          if(is_split && byte_buf.size() > 0) begin
            split_md_offset = byte_buf[0].md_offset;
            split_md_size   = byte_buf[0].md_size;
          end

          // Build the TX item
          tx_item        = md_item_mon::type_id::create("tx_item");
          tx_item.offset = ctrl_offset;

          // First copy carry-over bytes
          foreach(partial_buf[i])
            tx_item.data.push_back(partial_buf[i].val);

          // Then take bytes_needed bytes from byte_buf
          for(int i = 0; i < bytes_needed; i++)
            tx_item.data.push_back(byte_buf.pop_front().val);

          partial_buf.delete();

          // Emit prediction to scoreboard and increment uncapped pending counter.
          do_tx_lvl_up();
          tx_pending++;
          port_out_tx.write(tx_item);

          `uvm_info("TX_FIFO", $sformatf("TX FIFO push - level:%0d item:%0s",
                    tx_lvl, tx_item.convert2string()), UVM_LOW)

          // Emit split coverage info when a real split occurred
          if(is_split) begin
            algn_split_info info = algn_split_info::type_id::create("info");
            info.ctrl_offset      = ctrl_offset;
            info.ctrl_size        = ctrl_size;
            info.md_offset        = split_md_offset;
            info.md_size          = split_md_size;
            info.num_bytes_needed = split_num_bytes;
            port_out_split_info.write(info);
          end
        end
        // Loop: try to produce another output word from remaining bytes
      end
    endfunction

    // -----------------------------------------------------------------------
    // send_exp_irq_task
    // -----------------------------------------------------------------------
    protected virtual task send_exp_irq_task();
      algn_vif vif = env_config.get_vif();
      proc_irq = process::self();
      forever begin
        @(negedge vif.clk);
        if(exp_irq == 1) begin
          port_out_irq.write(exp_irq);
          exp_irq = 0;
        end
      end
    endtask

    // -----------------------------------------------------------------------
    // Analysis port callbacks
    // -----------------------------------------------------------------------

    virtual function void write_in_rx(md_item_mon item_mon);
      // Process at ITEM_START only (get_end_time()==-1)
      if(item_mon.get_end_time() != -1) return;

      begin
        md_response exp_response = get_exp_response(item_mon);
        case(exp_response)
          MD_ERR: begin
            inc_cnt_drop(exp_response);
            port_out_rx.write(exp_response);
          end
          MD_OKAY: begin
            port_out_rx.write(MD_OKAY);

            // Push payload bytes into byte_buf tagged with source item info
            foreach(item_mon.data[i]) begin
              algn_byte_entry e;
              e.val       = item_mon.data[i];
              e.md_offset = item_mon.offset;
              e.md_size   = item_mon.data.size();
              byte_buf.push_back(e);
            end

            do_rx_lvl_up();

            `uvm_info("RX_FIFO", $sformatf("RX push - level:%0d buf_bytes:%0d",
                      rx_lvl, byte_buf.size()), UVM_LOW)

            // Run the alignment engine — may produce 0 or more TX items
            run_align();

            do_rx_lvl_down();
          end
          default:
            `uvm_fatal("ALGORITHM_ISSUE",
                       $sformatf("Unsupported exp_response: %0s", exp_response.name()))
        endcase
      end
    endfunction

    virtual function void write_in_tx(md_item_mon item_mon);
      // Track TX level down at ITEM_END
      if(item_mon.get_end_time() != -1) begin
        do_tx_lvl_down();
        if(tx_pending > 0) tx_pending--;
        `uvm_info("TX_FIFO", $sformatf("TX FIFO pop - level:%0d pending:%0d item:%0s",
                  tx_lvl, tx_pending, item_mon.convert2string()), UVM_LOW)
      end
    endfunction

  endclass

`endif