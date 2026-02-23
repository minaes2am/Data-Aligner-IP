`ifndef ALGN_TEST_BASE_SV
  `define ALGN_TEST_BASE_SV
   
   `include "uvm_macros.svh"
   `include "algn_env.sv"
   `include "algn_test_defines.sv"

  import uvm_pkg::*;

  class algn_test_base extends uvm_test;
    
    //Environment instance
    algn_env#(`ALGN_TEST_ALGN_DATA_WIDTH) env;

    `uvm_component_utils(algn_test_base)
    
    function new(string name = "algn_test_base", uvm_component parent);
      super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      
      env = algn_env#(`ALGN_TEST_ALGN_DATA_WIDTH)::type_id::create("env", this);
    endfunction
    
  endclass

`endif
