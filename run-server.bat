@echo off
rem ================================================================
rem  XingChen4-29B Server - Edit parameters below
rem ================================================================

rem  Model file name (place GGUF files in this same folder)
set MODEL=xingchen4-iq4-00001-of-00002.gguf

rem  GPU layers (-1 or 999 = all, 0 = CPU only)
set NGL=999

rem  Context window size
set CTX=65536

rem  Max tokens to generate
set NTOKENS=8192

rem  Flash attention (on/off)
set FA=on

rem  KV cache quantization (q8_0 saves VRAM, f16 = no quant)
set CACHEK=q8_0
set CACHEV=q8_0

rem  Server port
set PORT=8086

rem  Host (0.0.0.0 = allow LAN access, 127.0.0.1 = local only)
set HOST=0.0.0.0

rem  Static files dir (leave empty if UI is embedded in exe)
set STATICPATH=

rem ================================================================
rem  Do not edit below unless you know what you are doing
rem ================================================================

echo Starting XingChen4-29B Server...
echo   Model:  %MODEL%
echo   Port:   %PORT%
echo   NGL:    %NGL%
echo   Ctx:    %CTX%
echo   Tokens: %NTOKENS%
echo   FA:     %FA%
echo.
echo Press Ctrl+C to stop.
echo.

cd /d "%~dp0"

start "" "http://127.0.0.1:%PORT%"

if "%STATICPATH%"=="" (
    llama-server.exe -m "%MODEL%" -ngl %NGL% -c %CTX% -n %NTOKENS% -fa %FA% --cache-type-k %CACHEK% --cache-type-v %CACHEV% --host %HOST% --port %PORT%
) else (
    llama-server.exe -m "%MODEL%" -ngl %NGL% -c %CTX% -n %NTOKENS% -fa %FA% --cache-type-k %CACHEK% --cache-type-v %CACHEV% --host %HOST% --port %PORT% --path "%STATICPATH%"
)
pause
