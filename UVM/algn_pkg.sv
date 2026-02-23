`ifndef ALGN_PKG_SV
  `define ALGN_PKG_SV

  `include "uvm_macros.svh"
  `include "apb_pkg.sv"
  `include "md_pkg.sv"
  `include "algn_reg_pkg.sv"

  `include "algn_if.sv"

  package algn_pkg;
    import uvm_pkg::*;
    import uvm_ext_pkg::*;
    import apb_pkg::*;
    import md_pkg::*;
    import algn_reg_pkg::*;

    `include "algn_types.sv"
    `include "algn_env_config.sv"
    `include "algn_clr_cnt_drop.sv"
    `include "algn_split_info.sv"
    `include "algn_model.sv"
    `include "algn_coverage.sv"
    `include "algn_reg_access_status_info.sv"
    `include "algn_reg_predictor.sv"
    `include "algn_scoreboard.sv"
    `include "algn_virtual_sequencer.sv"
    `include "algn_env.sv"

    `include "algn_seq_reg_config.sv"

    `include "algn_virtual_sequence_base.sv"
    `include "algn_virtual_sequence_slow_pace.sv"
    `include "algn_virtual_sequence_reg_access_random.sv"
    `include "algn_virtual_sequence_reg_access_unmapped.sv"
    `include "algn_virtual_sequence_reg_config.sv"
    `include "algn_virtual_sequence_reg_status.sv"
    `include "algn_virtual_sequence_rx.sv"
    `include "algn_virtual_sequence_rx_err.sv"

  endpackage

`endif
