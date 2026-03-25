@echo off
REM XAI Hypoglycemia Predictor - Demo Simulation
REM Compile and run XAI demo testbench with clean output for screenshots

echo ============================================================
echo XAI Hypoglycemia Predictor - Demo Simulation
echo ============================================================
echo.

cd /d "%~dp0"

REM Create simulation executable
echo Compiling XAI demo testbench...
iverilog -o sim_xai_demo.vvp ^
    src/input_buffer.v ^
    src/conv1d_engine_seq.v ^
    src/batchnorm_engine_seq.v ^
    src/pooling_engine.v ^
    src/dense_layer_seq.v ^
    src/control_unit_opt.v ^
    src/hypoglycemia_predictor_opt.v ^
    src/output_comparator.v ^
    src/activation_unit.v ^
    src/trend_calculator.v ^
    src/min_detector.v ^
    src/rate_of_change.v ^
    src/reason_encoder.v ^
    src/hypoglycemia_predictor_xai.v ^
    tb/tb_xai_demo.v

if errorlevel 1 (
    echo ERROR: Compilation failed!
    pause
    exit /b 1
)

echo Compilation successful!
echo.
echo Running XAI demo simulation...
echo ============================================================
echo.

REM Run simulation and capture output
vvp sim_xai_demo.vvp > sim_output/xai_demo_output.txt 2>&1

REM Display output
type sim_output\xai_demo_output.txt

echo.
echo ============================================================
echo Simulation complete!
echo Output saved to: sim_output\xai_demo_output.txt
echo ============================================================
echo.
echo Ready for screenshots! Open sim_output\xai_demo_output.txt
echo to view the formatted XAI demonstration output.
pause
