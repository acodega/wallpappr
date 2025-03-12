#!/bin/zsh --no-rcs

# wallpappr 1.0
# An easy to deploy dynamic wallpaper chooser for Self Service
# https://github.com/acodega/wallpappr
# Released under MIT License

# --- Configuration ---
myOrg="Contoso"
pkgReceipt="com.$myOrg.wallpaper.plist"
wallpaperDir="/Library/Application Support/$myOrg/wallpapers"
desktopprApp="/usr/local/bin/desktoppr"
dialogPath="/usr/local/bin/dialog"

# --- Get current user ---
currentUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
if [[ -z "$currentUser" || "$currentUser" == "loginwindow" ]]; then
    echo "No user logged in, cannot proceed"
    exit 0
fi
uid=$(id -u "$currentUser")

# --- Helper function to run commands as the current user ---
runAsUser() {
    launchctl asuser "$uid" sudo -u "$currentUser" "$@"
}

# --- Ensure required tools are installed ---
# Install swiftDialog if needed
if [ ! -f "$dialogPath" ]; then
    echo "Installing swiftDialog..."
    jamf policy -event install-swiftdialog
fi

# Install desktoppr if needed
if [ ! -f "$desktopprApp" ]; then
    echo "Installing desktoppr..."
    jamf policy -event install-desktoppr-ondemand
fi

# Install wallpapers if needed
if [ ! -f "/var/db/receipts/$pkgReceipt" ]; then
    echo "Installing wallpaper..."
    jamf policy -event install-wallpaper
fi

# Verify wallpaper directory exists
if [ ! -d "$wallpaperDir" ]; then
    echo "Wallpaper directory not found: $wallpaperDir"
    exit 1
fi

# --- Helper function to create preview images ---
generatePreview() {
    local wallpaperPath="$1"
    local previewPath="${wallpaperPath%.*}-preview.png"

    if [ ! -f "$previewPath" ] && [ -w "$(dirname "$previewPath")" ]; then
        # Generate preview with sips - 512px width while maintaining aspect ratio
        sips -Z 512 "$wallpaperPath" --out "$previewPath" >/dev/null 2>&1
    fi

    # Return success if preview exists
    [ -f "$previewPath" ]
}

# --- Find wallpaper files ---
echo "Scanning for wallpapers..."
# Get all PNG files (excluding previews)
wallpaperFiles=()
while IFS= read -r file; do
    if [[ "$file" != *"-preview.png" ]]; then
        wallpaperFiles+=("$file")
    fi
done < <(find "$wallpaperDir" -type f -name "*.png" | sort)

# Exit if no wallpapers found
if [ ${#wallpaperFiles[@]} -eq 0 ]; then
    echo "No wallpaper files found"
    exit 1
fi
echo "Found ${#wallpaperFiles[@]} wallpapers"

# --- Prepare for dialog display ---
# Basic dialog settings
dialogOptions=(
    --title "$myOrg Wallpaper Selector"
    --button1text "Set Wallpaper"
    --button2text "Cancel"
    --icon none
    --width 600
    --height 525
    --movable
    --ontop
    --windowbuttons close,min
    --timer 300
    --hidetimerbar

)

# Process wallpapers for display
wallpaperNames=()
wallpaperPaths=()

for wallpaperPath in "${wallpaperFiles[@]}"; do
    # Create preview image if needed
    previewPath="${wallpaperPath%.*}-preview.png"
    if [ ! -f "$previewPath" ]; then
        generatePreview "$wallpaperPath" || continue
    fi

    # Get nice display name for the wallpaper
    baseName=$(basename "$wallpaperPath" .png)
    description=$(mdls -name kMDItemDescription "$wallpaperPath" 2>/dev/null | awk -F'"' '{print $2}')

    if [[ -z "$description" || "$description" == "(null)" ]]; then
        # Convert filename to readable format (capitalize words, replace dashes/underscores with spaces)
        wallpaperName=$(echo "$baseName" | sed -E 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    else
        wallpaperName="$description"
    fi

    # Add to our collection
    wallpaperNames+=("$wallpaperName")
    wallpaperPaths+=("$wallpaperPath")

    # Add to dialog display,
    dialogOptions+=(--image "$previewPath" --imagecaption "$wallpaperName")
done

# Exit if no valid wallpapers with previews
if [ ${#wallpaperNames[@]} -eq 0 ]; then
    echo "No valid wallpapers found"
    exit 1
fi

# Add dropdown with wallpaper names
wallpaperNamesString=$(
    IFS=,
    echo "${wallpaperNames[*]}"
)
dialogOptions+=(--selecttitle "Choose a wallpaper",dropdown,required --selectvalues "$wallpaperNamesString")

# --- Show dialog and get user selection ---
echo "Displaying wallpaper selection dialog..."
dialogOutput=$("$dialogPath" "${dialogOptions[@]}")
exitCode=$?

# --- Process the result based on exit code ---
case $exitCode in
0) # User clicked "Set Wallpaper"
    # Extract selection information
    selectedWallpaperName=$(echo "$dialogOutput" | grep '"Choose a wallpaper" :' | sed 's/"Choose a wallpaper" : "\(.*\)"/\1/')
    selectedIndex=$(echo "$dialogOutput" | grep '"SelectedIndex" :' | awk '{print $NF}')

    if [[ -z "$selectedIndex" || ! "$selectedIndex" =~ ^[0-9]+$ ]]; then
        echo "Invalid selection returned from dialog"
        exit 1
    fi

    # Get wallpaper info by index
    selectedIndex=$((selectedIndex + 0))
    wallpaperChoice="${wallpaperPaths[$selectedIndex]}"
    wallpaperName="${wallpaperNames[$selectedIndex]}"

    # Verify selection - handle any mismatch between name and index
    if [[ "$selectedWallpaperName" != "$wallpaperName" ]]; then
        echo "Correcting wallpaper selection..."
        # Search for the exact matching wallpaper by name
        for i in {0..${#wallpaperNames[@]}}; do
            if [[ "${wallpaperNames[$i]}" == "$selectedWallpaperName" ]]; then
                wallpaperChoice="${wallpaperPaths[$i]}"
                wallpaperName="${wallpaperNames[$i]}"
                break
            fi
        done
    fi

    # Apply the wallpaper
    if [ -n "$wallpaperChoice" ]; then
        echo "Setting wallpaper: $wallpaperName"
        runAsUser $desktopprApp "$wallpaperChoice"

        # Verify the change was successful
        currentWallpaper=$(runAsUser $desktopprApp)
        if [ "$currentWallpaper" = "$wallpaperChoice" ]; then
            echo "Wallpaper successfully changed to $wallpaperName"
            # Run Jamf recon in background
            jamf recon &
            exit 0
        else
            echo "Failed to set wallpaper"
            exit 1
        fi
    else
        echo "Failed to find selected wallpaper"
        exit 1
    fi
    ;;

2) # User clicked "Cancel"
    echo "User canceled selection"
    exit 0
    ;;

4) # Timer expired
    echo "Timer expired"
    exit 0
    ;;

10) # User quit
    echo "User quit"
    exit 0
    ;;

*) # Other exit codes
    echo "Dialog exited with code $exitCode"
    exit 0
    ;;
esac
