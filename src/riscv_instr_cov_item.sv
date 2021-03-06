class riscv_instr_cov_item extends riscv_instr;

  typedef enum bit[1:0] {
    POSITIVE, NEGATIVE
  } operand_sign_e;

  typedef enum bit[1:0] {
    DIV_NORMAL, DIV_BY_ZERO, DIV_OVERFLOW
  } div_result_e;

  typedef enum bit[1:0] {
    EQUAL, LARGER, SMALLER
  } compare_result_e;

  typedef enum bit [1:0] {
    IDENTICAL, OPPOSITE, SIMILAR, DIFFERENT
  } logical_similarity_e;

  typedef enum bit[2:0] {
    NORMAL_VAL, MIN_VAL, MAX_VAL, ZERO_VAL
  } special_val_e;

  rand bit [XLEN-1:0]   rs1_value;
  rand bit [XLEN-1:0]   rs2_value;
  rand bit [XLEN-1:0]   rd_value;
  rand riscv_fpr_t      fs1;
  rand riscv_fpr_t      fs2;
  rand riscv_fpr_t      fs3;
  rand riscv_fpr_t      fd;
  rand bit [XLEN-1:0]   fs1_value;
  rand bit [XLEN-1:0]   fs2_value;
  rand bit [XLEN-1:0]   fs3_value;
  rand bit [XLEN-1:0]   fd_value;
  bit [31:0]            binary;
  bit [XLEN-1:0]        pc;
  bit [XLEN-1:0]        mem_addr;

  bit                   unaligned_pc;
  bit                   unaligned_mem_access;
  bit                   compressed;
  bit                   branch_hit;
  div_result_e          div_result;
  operand_sign_e        rs1_sign;
  operand_sign_e        rs2_sign;
  operand_sign_e        fs1_sign;
  operand_sign_e        fs2_sign;
  operand_sign_e        fs3_sign;
  operand_sign_e        imm_sign;
  operand_sign_e        rd_sign;
  operand_sign_e        fd_sign;
  hazard_e              gpr_hazard;
  hazard_e              lsu_hazard;
  special_val_e         rs1_special_val;
  special_val_e         rs2_special_val;
  special_val_e         rd_special_val;
  special_val_e         imm_special_val;
  compare_result_e      compare_result;
  logical_similarity_e  logical_similarity;
  three_instr_seq_e     three_instr_seq;
  string                trace;

  `VECTOR_INCLUDE("riscv_instr_cov_item_inc_declares.sv")

  `uvm_object_utils(riscv_instr_cov_item)
  `uvm_object_new

  virtual function void pre_sample();
    unaligned_pc = (pc[1:0] != 2'b00);
    rs1_sign = get_operand_sign(rs1_value);
    rs2_sign = get_operand_sign(rs2_value);
    rd_sign = get_operand_sign(rd_value);
    fs1_sign = get_operand_sign(fs1_value);
    fs2_sign = get_operand_sign(fs2_value);
    fs3_sign = get_operand_sign(fs2_value);
    fd_sign = get_operand_sign(fd_value);
    imm_sign = get_imm_sign(imm);
    rs1_special_val = get_operand_special_val(rs1_value);
    rd_special_val = get_operand_special_val(rd_value);
    rs2_special_val = get_operand_special_val(rs2_value);
    if ((format != R_FORMAT) && (format != CR_FORMAT)) begin
      imm_special_val = get_imm_special_val(imm);
    end
    if (category inside {COMPARE, BRANCH}) begin
      compare_result = get_compare_result();
    end
    if (category inside {LOAD, STORE}) begin
      mem_addr = rs1_value + imm;
      unaligned_mem_access = is_unaligned_mem_access();
      if (unaligned_mem_access) begin
        `uvm_info(`gfn, $sformatf("Unaligned: %0s, mem_addr:%0x", instr_name.name(), mem_addr),
                  UVM_HIGH)
      end
    end
    if (category == LOGICAL) begin
      logical_similarity = get_logical_similarity();
    end
    if (category == BRANCH) begin
      branch_hit = is_branch_hit();
    end
    if (instr_name inside {DIV, DIVU, REM, REMU, DIVW, DIVUW, REMW, REMUW}) begin
      div_result = get_div_result();
    end
  endfunction

  function operand_sign_e get_operand_sign(bit [XLEN-1:0] value);
    if (value[XLEN-1]) begin
      return NEGATIVE;
    end else begin
      return POSITIVE;
    end
  endfunction

  function bit is_unaligned_mem_access();
    if ((instr_name inside {LWU, LD, SD, C_LD, C_SD}) && (mem_addr % 8 != 0)) begin
      return 1'b1;
    end else if ((instr_name inside {LW, SW, C_LW, C_SW}) && (mem_addr % 4 != 0)) begin
      return 1'b1;
    end else if ((instr_name inside {LH, LHU, SH}) && (mem_addr % 2 != 0)) begin
      return 1'b1;
    end begin
      return 1'b0;
    end
  endfunction

  function operand_sign_e get_imm_sign(bit [31:0] value);
    if (value[31]) begin
      return NEGATIVE;
    end else begin
      return POSITIVE;
    end
  endfunction

  function div_result_e get_div_result();
    if (rs2_value == 0) begin
      return DIV_BY_ZERO;
    end else if ((rs2_value == '1) && (rs1_value == (1'b1 << (XLEN-1))))
      return DIV_OVERFLOW;
    else
      return DIV_NORMAL;
  endfunction

  function special_val_e get_operand_special_val(bit [XLEN-1:0] value);
    if (value == 0) begin
      return ZERO_VAL;
    end else if (value == '1 << (XLEN-1)) begin
      return MIN_VAL;
    end else if (value == '1 >> 1) begin
      return MAX_VAL;
    end else begin
      return NORMAL_VAL;
    end
  endfunction

  function special_val_e get_imm_special_val(bit [31:0] value);
    if (value == 0) begin
      return ZERO_VAL;
    end else if (format == U_FORMAT) begin
      // unsigend immediate value
      bit [31:0] max_val;
      max_val = (1 << imm_len)-1;
      if (value == '0) begin
        return MIN_VAL;
      end
      if (value == max_val) begin
        return MAX_VAL;
      end
    end else begin
      // signed immediate value
      int signed max_val, min_val;
      max_val =  2 ** (imm_len-1) - 1;
      min_val = -2 ** (imm_len-1);
      if (min_val == $signed(value)) begin
        return MIN_VAL;
      end
      if (max_val == $signed(value)) begin
        return MAX_VAL;
      end
    end
    return NORMAL_VAL;
  endfunction

  function compare_result_e get_compare_result();
    bit [XLEN-1:0] val1, val2;
    val1 = rs1_value;
    val2 = (format == I_FORMAT) ? imm : rs2_value;
    if (val1 == val2) begin
      return EQUAL;
    end else if (val1 < val2) begin
      return SMALLER;
    end else begin
      return LARGER;
    end
  endfunction

  function bit is_branch_hit();
    case(instr_name)
      BEQ    : is_branch_hit = (rs1_value == rs2_value);
      C_BEQZ : is_branch_hit = (rs1_value == 0);
      BNE    : is_branch_hit = (rs1_value == rs2_value);
      C_BNEZ : is_branch_hit = (rs1_value != 0);
      BLT    : is_branch_hit = ($signed(rs1_value) <  $signed(rs2_value));
      BGE    : is_branch_hit = ($signed(rs1_value) >  $signed(rs2_value));
      BLTU   : is_branch_hit = (rs1_value < rs2_value);
      BGEU   : is_branch_hit = (rs1_value > rs2_value);
      default: `uvm_error(get_name(), $sformatf("Unexpected instr %0s", instr_name.name()))
    endcase
    return is_branch_hit;
  endfunction

  function logical_similarity_e get_logical_similarity();
    bit [XLEN-1:0] val1, val2;
    int bit_difference;
    val1 = rs1_value;
    val2 = (format == I_FORMAT) ? imm : rs2_value;
    bit_difference = $countones(val1 ^ val2);
    if (val1 == val2)
      return IDENTICAL;
    else if (bit_difference == 32)
      return OPPOSITE;
    else if (bit_difference < 5)
      return SIMILAR;
    else
      return DIFFERENT;
  endfunction

  function void check_hazard_condition(riscv_instr_cov_item pre_instr);
    riscv_reg_t gpr;
    if (pre_instr.has_rd) begin
      if ((has_rs1 && (rs1 == pre_instr.rd)) || (has_rs2 && (rs2 == pre_instr.rd))) begin
        gpr_hazard = RAW_HAZARD;
      end else if (has_rd && (rd == pre_instr.rd)) begin
        gpr_hazard = WAW_HAZARD;
      end else if (has_rd && ((pre_instr.has_rs1 && (pre_instr.rs1 == rd)) ||
                              (pre_instr.has_rs2 && (pre_instr.rs2 == rd)))) begin
        gpr_hazard = WAR_HAZARD;
      end else begin
        gpr_hazard = NO_HAZARD;
      end
    end
    if (category == LOAD) begin
      if ((pre_instr.category == STORE) && (pre_instr.mem_addr == mem_addr)) begin
        lsu_hazard = RAW_HAZARD;
      end else begin
        lsu_hazard = NO_HAZARD;
      end
    end
    if (category == STORE) begin
      if ((pre_instr.category == STORE) && (pre_instr.mem_addr == mem_addr)) begin
        lsu_hazard = WAW_HAZARD;
      end else if ((pre_instr.category == LOAD) && (pre_instr.mem_addr == mem_addr)) begin
        lsu_hazard = WAR_HAZARD;
      end else begin
        lsu_hazard = NO_HAZARD;
      end
    end
    `uvm_info(`gfn, $sformatf("Pre:%0s, Cur:%0s, Hazard: %0s/%0s",
                              pre_instr.convert2asm(), this.convert2asm(),
                              gpr_hazard.name(), lsu_hazard.name()), UVM_FULL)
  endfunction



 function void three_instr_func(riscv_instr_cov_item prev_instr_seq, prev2_instr_seq);
	  static int ld_ld_ld_count;
	  static int sr_ld_ld_count;
	  static int ld_ld_sr_count;
	  static int ld_sr_sr_count;

	 $display("Inside three_seq_instr");
	  if(category == LOAD) begin
            $display("Category = LOAD");
	    if(prev2_instr_seq.category == LOAD && prev_instr_seq.category == LOAD) begin
                   three_instr_seq = LOAD_LOAD_LOAD;
	           ld_ld_ld_count++;
	          `uvm_info(`gfn, $sformatf("ld_ld_ld_cnt = %0d",ld_ld_ld_count),UVM_LOW)
	          `uvm_info(`gfn, $sformatf("SEQ: Fst_instr:%0s, Sec_instr:%0s, Thrd_instr:%0s, Seq: %0s/%0s/%0s", prev2_instr_seq.convert2asm(), 
                   prev_instr_seq.convert2asm(), this.convert2asm(), three_instr_seq.name(), three_instr_seq.name(), three_instr_seq.name()),UVM_LOW)
	     end		  
	     else if(prev2_instr_seq.category == STORE && prev_instr_seq.category == LOAD) begin
                   three_instr_seq = STORE_LOAD_LOAD;
	           sr_ld_ld_count++;
	           `uvm_info(`gfn, $sformatf("sr_ld_ld_cnt = %0d",sr_ld_ld_count),UVM_LOW)
                   `uvm_info(`gfn, $sformatf("SEQ: Fst_instr:%0s, Sec_instr:%0s, Thrd_instr:%0s, Seq: %0s/%0s/%0s", prev2_instr_seq.convert2asm(), 
                    prev_instr_seq.convert2asm(), this.convert2asm(), three_instr_seq.name(), three_instr_seq.name(), three_instr_seq.name()),UVM_LOW)
  	     end
  	     else
	       three_instr_seq = NO_SEQ;
	  end


          if(category == STORE) begin
            $display("Category = STORE");
	     if(prev2_instr_seq.category == LOAD && prev_instr_seq.category == LOAD) begin
                three_instr_seq = LOAD_LOAD_STORE;
	        ld_ld_sr_count++;
	       `uvm_info(`gfn, $sformatf("ld_ld_sr_cnt = %0d",ld_ld_sr_count),UVM_LOW)
               `uvm_info(`gfn, $sformatf("SEQ: Fst_instr:%0s, Sec_instr:%0s, Thrd_instr:%0s, Seq: %0s/%0s/%0s", prev_instr_seq.convert2asm(), 
                prev2_instr_seq.convert2asm(), this.convert2asm(), three_instr_seq.name(), three_instr_seq.name(), three_instr_seq.name()),UVM_LOW)  
	     end		  
	     else if(prev2_instr_seq.category == LOAD && prev_instr_seq.category == STORE) begin
                three_instr_seq = LOAD_STORE_STORE;
	        ld_sr_sr_count++;
	       `uvm_info(`gfn, $sformatf("ld_sr_sr_cnt = %0d",ld_sr_sr_count),UVM_LOW)
               `uvm_info(`gfn, $sformatf("SEQ: Fst_instr:%0s, Sec_instr:%0s, Thrd_instr:%0s, Seq: %0s/%0s/%0s", prev2_instr_seq.convert2asm(), 
                prev_instr_seq.convert2asm(), this.convert2asm(), three_instr_seq.name(), three_instr_seq.name(), three_instr_seq.name()),UVM_LOW);
  	     end
  	     else
	       three_instr_seq = NO_SEQ;
	  end
	 
  endfunction : three_instr_func

  virtual function void sample_cov();
    pre_sample();
  endfunction

endclass
