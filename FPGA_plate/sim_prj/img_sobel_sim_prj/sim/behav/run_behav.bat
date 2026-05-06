@echo off
set bin_path=D:/modelsim/win64pe
cd D:/2L676demo/img_sobel_sim_prj/img_sobel_sim_prj/sim/behav
call "%bin_path%/modelsim"   -do "do {run_behav_compile.tcl};do {run_behav_simulate.tcl}" -l run_behav_simulate.log
if "%errorlevel%"=="1" goto END
if "%errorlevel%"=="0" goto SUCCESS
:END
exit 1
:SUCCESS
exit 0
