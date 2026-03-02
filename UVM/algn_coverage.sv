`ifndef ALGN_COVERAGE_SV
  `define ALGN_COVERAGE_SV

  `include "uvm_macros.svh"
  `include "algn_env_config.sv"
  `include "algn_if.sv"
  `include "algn_split_info.sv"

   import uvm_pkg::*;
   import md_pkg::*;
   import apb_pkg::*; 
   import uvm_ext_pkg::*;
 
  `uvm_analysis_imp_decl(_in_split_info) 

  class algn_coverage extends uvm_component implements uvm_ext_reset_handler;
    
    //Analysis implementation port for split information from model
    uvm_analysis_imp_in_split_info#(algn_split_info, algn_coverage) port_in_split_info;
    
    covergroup cover_split with function sample(algn_split_info info);
      option.per_instance = 1;

      ctrl_offset : coverpoint info.ctrl_offset {
        option.comment = "Value of CTRL.OFFSET during a split (ctrl_size=1 never creates splits; offset=1,3 require ctrl_size=1)";
        bins values[]  = {0, 2};
      }
      
      ctrl_size : coverpoint info.ctrl_size {
        option.comment = "Value of CTRL.SIZE during a split (ctrl_size=1 never creates splits; ctrl_size=3 has no valid legal offset for 32-bit)";
        bins values[]  = {2, 4};
      }
      
      md_offset : coverpoint info.md_offset {
        option.comment = "Value of the MD transaction offset";
        bins values[]  = {[0:3]};
      }
      
      md_size : coverpoint info.md_size {
        option.comment = "Value of the MD transaction size (value 3 is structurally unreachable with current RX constraints)";
        bins values[]  = {1, 2, 4};
      }
      
      num_bytes_needed : coverpoint info.num_bytes_needed {
        option.comment = "Number of bytes needed during the split";
        bins values[]  = {[1:3]};
      }

    endgroup

    `uvm_component_utils(algn_coverage)
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      port_in_split_info = new("port_in_split_info", this);
      
      cover_split = new();
      cover_split.set_inst_name($sformatf("%0s_%0s", get_full_name(), "cover_split"));

    endfunction
    
    virtual function void write_in_split_info(algn_split_info info);
      cover_split.sample(info);
    endfunction
    
    virtual function void handle_reset(uvm_phase phase);
      
    endfunction
    
    //Function to print the coverage information.
    //This is only to be able to visualize some basic coverage information
    //in EDA Playground.
    //DON'T DO THIS IN A REAL PROJECT!!!
    virtual function string coverage2string();
      string result = {
        $sformatf("\n   cover_split:            %03.2f%%", cover_split.get_inst_coverage()),
        $sformatf("\n      ctrl_offset:         %03.2f%%", cover_split.ctrl_offset.get_inst_coverage()),
        $sformatf("\n      ctrl_size:           %03.2f%%", cover_split.ctrl_size.get_inst_coverage()),
        $sformatf("\n      md_offset:           %03.2f%%", cover_split.md_offset.get_inst_coverage()),
        $sformatf("\n      md_size:             %03.2f%%", cover_split.md_size.get_inst_coverage()),
        $sformatf("\n      num_bytes_needed:    %03.2f%%", cover_split.num_bytes_needed.get_inst_coverage())
      };
 
      return result;
    endfunction

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);

      //IMPORTANT: DON'T DO THIS IN A REAL PROJECT!!!
      `uvm_info("COVERAGE", $sformatf("Coverage: %0s", coverage2string()), UVM_LOW)
    endfunction
  endclass

`endif