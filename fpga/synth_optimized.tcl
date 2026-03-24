# Vivado Synthesis Script for Optimized Hypoglycemia Predictor
# Run with: vivado -mode batch -source synth_optimized.tcl

puts "=========================================="
puts "OPTIMIZED RTL SYNTHESIS"
puts "=========================================="

# Project settings
set project_name "hypoglycemia_predictor_opt"
set project_dir "D:/final FPGA/fpga"
set src_dir "${project_dir}/src"
set part "xc7a35ticsg324-1L"

# Create project (force recreate)
create_project ${project_name} ${project_dir}/${project_name}_opt -part ${part} -force

# Add optimized source files
add_files -norecurse {
    D:/final FPGA/fpga/src/input_buffer.v
    D:/final FPGA/fpga/src/conv1d_engine_seq.v
    D:/final FPGA/fpga/src/batchnorm_engine_v2.v
    D:/final FPGA/fpga/src/pooling_engine.v
    D:/final FPGA/fpga/src/dense_layer_seq.v
    D:/final FPGA/fpga/src/control_unit_opt.v
    D:/final FPGA/fpga/src/hypoglycemia_predictor_opt.v
    D:/final FPGA/fpga/src/output_comparator.v
}

# Set top module
set_property top hypoglycemia_predictor_opt [current_fileset]

# Set synthesis options
# - Enable DSP inference
# - Enable resource sharing
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE Explore [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FSM_EXTRACTION one_hot [get_runs synth_1]

# Run synthesis
puts "Starting synthesis..."
launch_runs synth_1
wait_on_run synth_1

# Open synthesized design
open_run synth_1

# Generate utilization report
report_utilization -file ${project_dir}/opt_utilization.rpt

# Generate timing report  
report_timing_summary -file ${project_dir}/opt_timing.rpt

# Print summary
puts ""
puts "=========================================="
puts "SYNTHESIS COMPLETE"
puts "=========================================="
puts ""
puts "Results saved to:"
puts "  - ${project_dir}/opt_utilization.rpt"
puts "  - ${project_dir}/opt_timing.rpt"
puts ""
puts "Expected improvements:"
puts "  LUTs: 32,623 (original) -> 12,020 (current) -> target <10,000"
puts "  DSPs: 90 (original) -> 89 (current) -> target <20"
puts "  BRAM: 0 -> target 2-3"
puts ""
puts "Next step: Run opt_design for further optimization"
puts "  launch_runs impl_1 -step opt_design"
