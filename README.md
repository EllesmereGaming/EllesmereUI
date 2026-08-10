# EllesmereUI

EllesmereUI is a lightweight framework and UI replacement suite for World of Warcraft.

## Packaging for Local Use

This addon uses the [BigWigs Packager](https://github.com/BigWigsMods/packager) to fetch its external library dependencies (such as `oUF`, `LibStub`, etc.), which are required for the addon to run correctly.

If you clone or download this repository directly, **it will not work out of the box** because those dependencies are not included in the source code. You must package the addon yourself locally.

### Prerequisites (macOS)

The packaging script requires Bash 4.3+ and Subversion (SVN) to fetch some external libraries. macOS does not ship with these by default anymore. 

You can easily install them using [Homebrew](https://brew.sh/):

```bash
brew install bash svn
```

### Running the Packager

1. Open your terminal and navigate to the root of the `EllesmereUI` project directory.
2. Run the following command to download and execute the packager script:

    **On macOS (using Homebrew bash):**
    ```bash
    curl -s https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh | /opt/homebrew/bin/bash
    ```

    **On Linux / Windows (with compatible bash available):**
    ```bash
    curl -s https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh | bash
    ```

3. Once the package script finishes, a hidden folder named `.release` will be created inside the project directory.
4. Inside the `.release` folder, you will find a generated `.zip` file as well as several unzipped folders (e.g., `EllesmereUI`, `EllesmereUINameplates`, `EllesmereUIUnitFrames`, etc.).
5. Copy all the generated AddOn folders from inside `.release` directly into your World of Warcraft `_retail_/Interface/AddOns/` folder.
6. Restart or `/reload` your World of Warcraft client.

## Project Structure

- **Core Initialization:** 
  - `EllesmereUI_Startup.lua` runs early in the loading process.
  - `EllesmereUI.lua` handles shared initialization once loaded.
- **Key Modules:** The UI is cleanly separated into specialized modules (e.g., `EllesmereUIActionBars`, `EllesmereUIUnitFrames`, `EllesmereUICooldownManager`).

## Developer Workflow

- **`save.ps1`**: A PowerShell script to quickly commit and push your work in progress.
- **`release.ps1`**: A PowerShell script that tags and pushes a release, which triggers the BigWigs packager via `.github/workflows/release.yml` to automatically build the addon on GitHub Actions.
