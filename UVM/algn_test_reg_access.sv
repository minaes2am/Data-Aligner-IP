`ifndef ALGN_TEST_REG_ACCESS_SV
  `define ALGN_TEST_REG_ACCESS_SV

  `include "uvm_macros.svh"
  `include "algn_virtual_sequence_reg_access_random.sv"
  `include "algn_test_base.sv"
  `include "algn_virtual_sequence_reg_access_unmapped.sv"

  import uvm_pkg::*;

  class algn_test_reg_access extends algn_test_base;
    
    //Number of register accesses
    protected int unsigned num_reg_accesses;

    //Number of unmapped accesses
    protected int unsigned num_unmapped_accesses;

    `uvm_component_utils(algn_test_reg_access)
    
    function new(string name = "algn_test_reg_access", uvm_component parent);
      super.new(name, parent);
      
      num_reg_accesses      = 100;
      num_unmapped_accesses = 100;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
      
      phase.raise_objection(this, "TEST_DONE");
      
      #(100ns);
      
      fork
        begin
          algn_virtual_sequence_reg_access_random seq = algn_virtual_sequence_reg_access_random::type_id::create("seq");
          
          void'(seq.randomize() with {
            num_accesses == num_reg_accesses;
          });
          
          seq.start(env.virtual_sequencer);
        end
        begin
          algn_virtual_sequence_reg_access_unmapped seq = algn_virtual_sequence_reg_access_unmapped::type_id::create("seq");
          
          void'(seq.randomize() with {
            num_accesses == num_unmapped_accesses;
          });
          
          seq.start(env.virtual_sequencer);
        end
      join
      
      #(100ns);
      
      phase.drop_objection(this, "TEST_DONE"); 
    endtask
    
  endclass

`endif
