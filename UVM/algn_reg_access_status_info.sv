`ifndef ALGN_REG_ACCESS_STATUS_INFO_SV
  `define ALGN_REG_ACCESS_STATUS_INFO_SV

   `include "uvm_macros.svh"

   import uvm_pkg::*;

  class algn_reg_access_status_info;
  
    const uvm_status_e status;
    
    const string info;
    
    function new(uvm_status_e status, string info);
      this.status = status;
      this.info   = info;
    endfunction
    
    static function algn_reg_access_status_info new_instance(uvm_status_e status, string info);
      algn_reg_access_status_info result = new(status, info);
      
      return result;
    endfunction
    
  endclass

`endif
