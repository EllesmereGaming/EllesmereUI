@echo off
setlocal enabledelayedexpansion

echo ================================================================
echo  EllesmereUI Installation Script
echo ================================================================
echo Because World of Warcraft Wrath of the Lich King (3.3.5a) does
echo not support nested add-on directories, this script will create
echo directory junctions in the parent AddOns directory pointing to
echo the sub-addons included in this repository. This allows the game
echo to discover and load them properly while keeping the repository
echo structure intact.
echo ================================================================
echo.

set /p confirm="Do you want to continue? (Y/N): "
if /i not "%confirm%"=="Y" (
    echo Installation aborted.
    pause
    exit /b 1
)

echo.

:: Iterate over all directories
for /d %%F in (*) do (
    set "folder_name=%%~nxF"

    :: Check if it has a .toc file matching the folder name
    if exist "!folder_name!\!folder_name!.toc" (
        if not exist "..\!folder_name!" (
            echo Creating directory junction for !folder_name! in parent directory...
            mklink /J "..\!folder_name!" "%CD%\!folder_name!"
        ) else (
            echo Junction or directory for !folder_name! already exists in parent directory, skipping...
        )
    )
)

echo Installation complete.
pause
