@echo off
setlocal enabledelayedexpansion

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
