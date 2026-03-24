@echo off
REM RTL Simulation Script for Hypoglycemia Predictor CNN
REM Uses Icarus Verilog (iverilog)
REM IMPORTANT: Must run from fpga/ directory where .mem files are located

setlocal
cd /d "%~dp0"

echo ============================================================
echo RTL Simulation - Hypoglycemia Predictor CNN
echo Working directory: %CD%
echo ============================================================
echo.

REM Create simulation output directory
if not exist sim_output mkdir sim_output

REM Compile and run tb_conv1d_engine
echo [1/5] Simulating tb_conv1d_engine...
iverilog -o sim_output\tb_conv1d_engine.vvp -s tb_conv1d_engine src\conv1d_engine.v tb\tb_conv1d_engine.v 2> sim_output\tb_conv1d_engine.log
if errorlevel 1 (
    echo ERROR: Compilation failed for tb_conv1d_engine
    type sim_output\tb_conv1d_engine.log
) else (
    vvp sim_output\tb_conv1d_engine.vvp > sim_output\tb_conv1d_engine.txt 2>&1
    type sim_output\tb_conv1d_engine.txt
)
echo.

REM Compile and run tb_batchnorm_engine
echo [2/5] Simulating tb_batchnorm_engine...
iverilog -o sim_output\tb_batchnorm_engine.vvp -s tb_batchnorm_engine src\batchnorm_engine.v tb\tb_batchnorm_engine.v 2> sim_output\tb_batchnorm_engine.log
if errorlevel 1 (
    echo ERROR: Compilation failed for tb_batchnorm_engine
    type sim_output\tb_batchnorm_engine.log
) else (
    vvp sim_output\tb_batchnorm_engine.vvp > sim_output\tb_batchnorm_engine.txt 2>&1
    type sim_output\tb_batchnorm_engine.txt
)
echo.

REM Compile and run tb_pooling_engine
echo [3/5] Simulating tb_pooling_engine...
iverilog -o sim_output\tb_pooling_engine.vvp -s tb_pooling_engine src\pooling_engine.v tb\tb_pooling_engine.v 2> sim_output\tb_pooling_engine.log
if errorlevel 1 (
    echo ERROR: Compilation failed for tb_pooling_engine
    type sim_output\tb_pooling_engine.log
) else (
    vvp sim_output\tb_pooling_engine.vvp > sim_output\tb_pooling_engine.txt 2>&1
    type sim_output\tb_pooling_engine.txt
)
echo.

REM Compile and run tb_dense_layer
echo [4/5] Simulating tb_dense_layer...
iverilog -o sim_output\tb_dense_layer.vvp -s tb_dense_layer src\dense_layer.v tb\tb_dense_layer.v 2> sim_output\tb_dense_layer.log
if errorlevel 1 (
    echo ERROR: Compilation failed for tb_dense_layer
    type sim_output\tb_dense_layer.log
) else (
    vvp sim_output\tb_dense_layer.vvp > sim_output\tb_dense_layer.txt 2>&1
    type sim_output\tb_dense_layer.txt
)
echo.

REM Compile and run tb_hypoglycemia_predictor (top-level)
echo [5/5] Simulating tb_hypoglycemia_predictor (TOP-LEVEL)...
iverilog -o sim_output\tb_hypoglycemia_predictor.vvp -s tb_hypoglycemia_predictor ^
    src\input_buffer.v ^
    src\conv1d_engine.v ^
    src\batchnorm_engine.v ^
    src\pooling_engine.v ^
    src\dense_layer.v ^
    src\output_comparator.v ^
    src\control_unit.v ^
    src\hypoglycemia_predictor.v ^
    tb\tb_hypoglycemia_predictor.v 2> sim_output\tb_hypoglycemia_predictor.log
if errorlevel 1 (
    echo ERROR: Compilation failed for tb_hypoglycemia_predictor
    type sim_output\tb_hypoglycemia_predictor.log
) else (
    vvp sim_output\tb_hypoglycemia_predictor.vvp > sim_output\tb_hypoglycemia_predictor.txt 2>&1
    type sim_output\tb_hypoglycemia_predictor.txt
)
echo.

echo ============================================================
echo SIMULATION COMPLETE
echo ============================================================
echo.
echo Results saved in: sim_output\
echo.

endlocal
