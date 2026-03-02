`ifndef ALGN_SCOREBOARD_SV
  `define ALGN_SCOREBOARD_SV

  `include "uvm_macros.svh"
  `include "algn_env_config.sv"
  `include "algn_if.sv"

   import uvm_pkg::*;
   import md_pkg::*;
   import apb_pkg::*; 
   import uvm_ext_pkg::*;
 
  `uvm_analysis_imp_decl(_in_model_rx)
  `uvm_analysis_imp_decl(_in_model_tx)
  `uvm_analysis_imp_decl(_in_model_irq)
  `uvm_analysis_imp_decl(_in_agent_rx)
  `uvm_analysis_imp_decl(_in_agent_tx)
 
  class algn_scoreboard extends uvm_component implements uvm_ext_reset_handler;
    
    //Pointer to the environment configuration
    algn_env_config env_config;
 
    //Analysis implementation port for receiving RX information from model
    //NOTE: This port is kept for backward compatibility but RX checking is now
    //      done self-sufficiently in write_in_agent_rx to avoid analysis-port
    //      ordering races in UVM 1.1d (Questa).
    uvm_analysis_imp_in_model_rx#(md_response, algn_scoreboard) port_in_model_rx;
    
    //Analysis implementation port for receiving TX information from model
    uvm_analysis_imp_in_model_tx#(md_item_mon, algn_scoreboard) port_in_model_tx;
    
    //Analysis implementation port for receiving IRQ information from model
    uvm_analysis_imp_in_model_irq#(bit, algn_scoreboard) port_in_model_irq;
    
    //Analysis implementation port for receiving RX information from RX MD agent
    uvm_analysis_imp_in_agent_rx#(md_item_mon, algn_scoreboard) port_in_agent_rx;
    
    //Analysis implementation port for receiving RX information from TX MD agent
    uvm_analysis_imp_in_agent_tx#(md_item_mon, algn_scoreboard) port_in_agent_tx;
    
    
    //Expected responses on RX interface
    protected md_response exp_rx_responses[$];
    
    //Expected items on TX interface
    protected md_item_mon exp_tx_items[$];
    
    //Expected interrupt requests
    protected bit exp_irqs[$];

    // When drain_mode=1, write_in_agent_tx silently discards incoming DUT TX
    // items WITHOUT popping exp_tx_items and WITHOUT raising any errors.
    // Set this during CTRL transitions so residual DUT pipeline output doesn't
    // corrupt the expected queue that holds predictions for the new batch.
    local bit drain_mode;
    
    
    
    //Processes associated with task exp_rx_response_watchdog()
    local process process_exp_rx_response_watchdog[$];
    
    //Processes associated with task exp_tx_item_watchdog()
    local process process_exp_tx_item_watchdog[$];
    
    //Processes associated with task exp_irq_watchdog()
    local process process_exp_irq_watchdog[$];
    
    //Process associated with task rcv_irq()
    local process process_rcv_irq;
    
    
    `uvm_component_utils(algn_scoreboard)
    
    virtual task run_phase(uvm_phase phase);
      rcv_irq_nb();
    endtask
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      port_in_model_rx  = new("port_in_model_rx",  this);
      port_in_model_tx  = new("port_in_model_tx",  this);
      port_in_model_irq = new("port_in_model_irq", this);
      port_in_agent_rx  = new("port_in_agent_rx",  this);
      port_in_agent_tx  = new("port_in_agent_tx",  this);
    endfunction
    
    virtual function void handle_reset(uvm_phase phase);
      exp_rx_responses.delete();
      exp_tx_items.delete();
      exp_irqs.delete();
      drain_mode = 0;
       
      kill_processes_from_queue(process_exp_rx_response_watchdog);
      kill_processes_from_queue(process_exp_tx_item_watchdog);
      kill_processes_from_queue(process_exp_irq_watchdog);
      
      if(process_rcv_irq != null) begin
        process_rcv_irq.kill();
        
        process_rcv_irq = null;
      end
      
      rcv_irq_nb();
    endfunction

    // Enable/disable drain mode.
    // In drain_mode=1 all incoming DUT TX items are silently discarded without
    // touching exp_tx_items.  This absorbs residual DUT TX output during a CTRL
    // transition without corrupting the expected queue.
    virtual function void set_drain_mode(bit enable);
      drain_mode = enable;
      `uvm_info("SCOREBOARD", $sformatf("drain_mode set to %0b", enable), UVM_MEDIUM)
    endfunction

    // Discard all pending expected TX items (called before CTRL changes so that
    // stale predictions from the old configuration are not compared against new output).
    virtual function void flush_tx_queue();
      int unsigned n = exp_tx_items.size();
      exp_tx_items.delete();
      kill_processes_from_queue(process_exp_tx_item_watchdog);
      if(n > 0)
        `uvm_info("SCOREBOARD",
          $sformatf("flush_tx_queue: discarded %0d stale expected TX items", n), UVM_MEDIUM)
    endfunction
    
    //Function to kill all the processes from a queue
    virtual function void kill_processes_from_queue(ref process processes[$]);
      while(processes.size() > 0) begin
        processes[0].kill();
        
        void'(processes.pop_front());
      end
    endfunction
    
    //Task for waiting for DUT to output its RX response
    protected virtual task exp_rx_response_watchdog(md_response response);
      algn_vif vif       = env_config.get_vif();
      int unsigned threshold = env_config.get_exp_rx_response_threshold();
      time start_time        = $time();
      
      repeat(threshold) begin
        @(posedge vif.clk);
      end 
      
      if(env_config.get_has_checks()) begin 
        `uvm_error("DUT_ERROR", $sformatf("The RX response, with value %0s, expected from time %0t, was not received after %0d clock cycles",
                                          response.name(), start_time, threshold))
      end 
    endtask
    
    //Task for waiting for DUT to output its TX item
    protected virtual task exp_tx_item_watchdog(md_item_mon item_mon);
      algn_vif vif       = env_config.get_vif();
      int unsigned threshold = env_config.get_exp_tx_item_threshold();
      time start_time        = $time();
      
      repeat(threshold) begin
        @(posedge vif.clk);
      end 
      
      if(env_config.get_has_checks()) begin 
        `uvm_error("DUT_ERROR", $sformatf("The TX item expected from time %0t, was not received after %0d clock cycles - item: %0s",
                                          start_time, threshold, item_mon.convert2string()))
      end 
    endtask
    
    //Task for waiting for DUT to output its IRQ
    protected virtual task exp_irq_watchdog(bit irq);
      algn_vif vif       = env_config.get_vif();
      int unsigned threshold = env_config.get_exp_irq_threshold();
      time start_time        = $time();
      
      repeat(threshold) begin
        @(posedge vif.clk);
      end 
      
      if(env_config.get_has_checks()) begin 
        `uvm_error("DUT_ERROR", $sformatf("The IRQ expected from time %0t, was not received after %0d clock cycles",
                                          start_time, threshold))
      end 
    endtask
    
    //Function to start the task exp_rx_response_watchdog()
    local function void exp_rx_response_watchdog_nb(md_response response);
      fork
        begin
          process p = process::self();
          
          process_exp_rx_response_watchdog.push_back(p);
          
          exp_rx_response_watchdog(response);
          
          if(process_exp_rx_response_watchdog.size() == 0) begin
            `uvm_fatal("ALGORITHM_ISSUE", "At the end of task exp_rx_response_watchdog the queue of processes process_exp_rx_response_watchdog is empty")
          end 
          
          void'(process_exp_rx_response_watchdog.pop_front());
        end
      join_none
    endfunction
    
    //Function to start the task exp_tx_item_watchdog()
    local function void exp_tx_item_watchdog_nb(md_item_mon item_mon);
      fork
        begin
          process p = process::self();
          
          process_exp_tx_item_watchdog.push_back(p);
          
          exp_tx_item_watchdog(item_mon);
          
          if(process_exp_tx_item_watchdog.size() == 0) begin
            `uvm_fatal("ALGORITHM_ISSUE", "At the end of task exp_tx_item_watchdog the queue of processes process_exp_tx_item_watchdog is empty")
          end 
          
          void'(process_exp_tx_item_watchdog.pop_front());
        end
      join_none
    endfunction
    
    //Function to start the task exp_irq_watchdog()
    local function void exp_irq_watchdog_nb(bit irq);
      fork
        begin
          process p = process::self();
          
          process_exp_irq_watchdog.push_back(p);
          
          exp_irq_watchdog(irq);
          
          if(process_exp_irq_watchdog.size() == 0) begin
            `uvm_fatal("ALGORITHM_ISSUE", "At the end of task exp_irq_watchdog the queue of processes process_exp_irq_watchdog is empty")
          end 
          
          void'(process_exp_irq_watchdog.pop_front());
        end
      join_none
    endfunction
    
    virtual function void write_in_model_rx(md_response response);
      if(exp_rx_responses.size() >= 8) begin
        `uvm_error("ALGORITHM_ISSUE", $sformatf("Something went wrong as there are already %0d entries in exp_rx_responses and just received one more",
                                                exp_rx_responses.size()))
      end 
      
      exp_rx_responses.push_back(response);
      
      exp_rx_response_watchdog_nb(response);
    endfunction

    virtual function void write_in_model_tx(md_item_mon item_mon);
      if(exp_tx_items.size() >= 32) begin
        `uvm_error("ALGORITHM_ISSUE", $sformatf("Something went wrong as there are already %0d entries in exp_tx_items and just received one more",
                                                exp_tx_items.size()))
      end 
      
      exp_tx_items.push_back(item_mon);
      
      exp_tx_item_watchdog_nb(item_mon);
    endfunction

    virtual function void write_in_model_irq(bit irq);
      if(exp_irqs.size() >= 5) begin
        `uvm_error("ALGORITHM_ISSUE", $sformatf("Something went wrong as there are already %0d entries in exp_irqs and just received one more",
                                                exp_irqs.size()))
      end 
      
      exp_irqs.push_back(irq);
      
      exp_irq_watchdog_nb(irq);
    endfunction

    // Compute the expected RX response locally using the same logic as the DUT (rx_ctrl.sv).
    // This makes the scoreboard self-sufficient and avoids any analysis-port ordering races
    // between model.write_in_rx firing port_out_rx and write_in_agent_rx being called.
    protected virtual function md_response compute_exp_rx_response(md_item_mon item_mon);
      int unsigned algn_data_width_bytes = env_config.get_algn_data_width() / 8;
      // Zero-size transactions are always errors
      if(item_mon.data.size() == 0)
        return MD_ERR;
      // Alignment check: (data_width_bytes + offset) % size must be 0
      if(((algn_data_width_bytes + item_mon.offset) % item_mon.data.size()) != 0)
        return MD_ERR;
      return MD_OKAY;
    endfunction

    virtual function void write_in_agent_rx(md_item_mon item_mon);
      // Only process completed items; skip ITEM_START notifications.
      // NOTE: is_active() is unreliable in Questa UVM 1.1d when transaction
      // recording is disabled. Use get_end_time()==-1 as the active check.
      if(item_mon.get_end_time() == -1) return;
      
      if(env_config.get_has_checks()) begin
        md_response exp_response = compute_exp_rx_response(item_mon);
        
        if(item_mon.response != exp_response) begin
          `uvm_error("DUT_ERROR", $sformatf("Mismatch detected for the RX response -> expected: %0s, received: %0s, item: %0s",
                                            exp_response.name(), item_mon.response.name(), item_mon.convert2string()))
        end
      end
      
      // Drain the model-predicted queue if available (for consistency tracking).
      // The queue may be empty if model port ordering differs — that is now handled
      // by compute_exp_rx_response above, so we just drain without erroring.
      if(exp_rx_responses.size() > 0) begin
        void'(exp_rx_responses.pop_front());
        if(process_exp_rx_response_watchdog.size() > 0) begin
          process_exp_rx_response_watchdog[0].kill();
          void'(process_exp_rx_response_watchdog.pop_front());
        end
      end
    endfunction

    virtual function void write_in_agent_tx(md_item_mon item_mon);
      // Only process completed items; skip ITEM_START notifications.
      // NOTE: is_active() is unreliable in Questa UVM 1.1d when transaction
      // recording is disabled. Use get_end_time()==-1 as the active check.
      if(item_mon.get_end_time() == -1) return;

      // In drain_mode silently discard the DUT TX item without touching
      // exp_tx_items.  Residual pipeline output during a CTRL transition must
      // NOT pop from the expected queue (which already holds predictions for the
      // new batch after flush) and must not raise any errors.
      if(drain_mode) return;
      
      if(exp_tx_items.size() == 0) begin
        if(env_config.get_has_checks()) begin
          `uvm_error("DUT_ERROR", $sformatf("Received TX item with no expected entry in queue - item: %0s", item_mon.convert2string()))
        end
        return;
      end
      
      begin
        md_item_mon exp_item = exp_tx_items.pop_front();
        
        if(process_exp_tx_item_watchdog.size() > 0) begin
          process_exp_tx_item_watchdog[0].kill();
          void'(process_exp_tx_item_watchdog.pop_front());
        end
        
        if(env_config.get_has_checks()) begin
          if(item_mon.data != exp_item.data) begin
            `uvm_error("DUT_ERROR", $sformatf("Mismatch detected for the TX data -> expected: %0s, received: %0s",
                                              exp_item.convert2string(), item_mon.convert2string()))
          end
          
          if(item_mon.offset != exp_item.offset) begin
            `uvm_error("DUT_ERROR", $sformatf("Mismatch detected for the TX offset -> expected: %0s, received: %0s",
                                              exp_item.convert2string(), item_mon.convert2string()))
          end
        end
      end
    endfunction
    
    //Task to collect IRQ information from DUT
    protected virtual task rcv_irq();
      algn_vif vif = env_config.get_vif();
      
      forever begin
        @(posedge vif.clk iff(vif.irq & vif.reset_n));
        
        if(exp_irqs.size() == 0) begin
          if(env_config.get_has_checks()) begin
              `uvm_error("DUT_ERROR", "Unexpected IRQ detected")
            end
          end
        else begin
          void'(exp_irqs.pop_front());

          if(process_exp_irq_watchdog.size() > 0) begin
            process_exp_irq_watchdog[0].kill();
            void'(process_exp_irq_watchdog.pop_front());
          end
        end
      end
    endtask
    
    //Function t start the rcv_irq() task
    local virtual function void rcv_irq_nb();
      if(process_rcv_irq != null) begin
        `uvm_fatal("ALGORITHM_ISSUE", "Can not start two instances of rcv_irq() tasks")
      end
      
      fork
        begin
          process_rcv_irq = process::self();
          
          rcv_irq();
          
          process_rcv_irq = null;
        end
      join_none
    endfunction

  endclass

`endif