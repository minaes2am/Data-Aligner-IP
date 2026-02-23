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
    
    //Number of MD RX transactions
    protected int unsigned num_md_rx_transactions;

    `uvm_component_utils(algn_test_random)
    
    function new(string name = "algn_test_random", uvm_component parent);
      super.new(name, parent);
      
      num_md_rx_transactions = 100;
    endfunction
     
    virtual task run_phase(uvm_phase phase); 
      uvm_status_e status;
      
      phase.raise_objection(this, "TEST_DONE");
       
      #(100ns);
       
      fork
        begin
          md_sequence_slave_response_forever seq = md_sequence_slave_response_forever::type_id::create("seq");
          
          seq.start(env.md_tx_agent.sequencer);
        end
      join_none
      
      repeat(2) begin
        if(env.model.is_empty()) begin
          algn_virtual_sequence_reg_config seq = algn_virtual_sequence_reg_config::type_id::create("seq");

          seq.set_sequencer(env.virtual_sequencer);

          void'(seq.randomize());

          seq.start(env.virtual_sequencer);
        end

        repeat(num_md_rx_transactions) begin
          algn_virtual_sequence_rx seq = algn_virtual_sequence_rx::type_id::create("seq");

          seq.set_sequencer(env.virtual_sequencer);

          void'(seq.randomize());

          seq.start(env.virtual_sequencer);
        end

        begin
          algn_vif vif = env.env_config.get_vif();

          repeat(100) begin
            @(posedge vif.clk);
          end 
        end 

        begin
          algn_virtual_sequence_reg_status seq = algn_virtual_sequence_reg_status::type_id::create("seq");

          void'(seq.randomize());

          seq.start(env.virtual_sequencer);
        end
      end
      
      #(500ns);
      
      phase.drop_objection(this, "TEST_DONE"); 
    endtask
    
  endclass

`endif
