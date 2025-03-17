# wallpappr
https://github.com/user-attachments/assets/3c1618ab-0675-475d-a1fb-e0dd06719299

An easy to deploy dynamic wallpaper chooser for Self Service

Wallpappr uses [swiftDialog](https://github.com/swiftdialog/swiftdialog) and [desktoppr](https://github.com/scriptingosx/desktoppr) to let a user change their wallpaper from a displayed collection of your organization wallpapers.

This gives you an easy to deploy and maintain method to provide multiple branded or themed wallpapers through Self Service.

From a local folder path, Wallpappr dynamically generates the list of wallpaper file paths and each wallpaper's friendly name to display. You simply need to deploy your wallpapers to `/Library/Application Support/YourOrg/wallpapers` and the script handles the rest. This is especially useful when you are deploying new seasonal or event wallpapers often.

Using `sip`, Wallpappr automatically handles generating the preview file (yourwallpaper-preview.png) if it doesn't exist. Otherwise, if swiftDialog loads full resolution images, it has to shrink them to display correctly and that causes a visual delay in the dialog box launching. When deploying a new wallpaper, only the full resolution image needs to be installed.


Wallpappr generates each wallpaper's "friendly name" two ways. It will use the `kMDItemDescription` file attribute when available, if not it tries to make a friendly name from the file name. Ex: `contoso-blue-waves.png` would become "Contoso Blue Waves". It also works if there are spaces or underscores between words.

Why use `kMDItemDescription`? Sometimes the friendly name you want doesn't make sense as a file name. `contoso-nyc-headquarters.png` would become Contoso Nyc Headquarters, instead of capitalizing NYC. Needing to use non alphanumeric characters (&, #, $) would also complicate things.

`kMDItemDescription` can be set by running `xattr -w com.apple.metadata:kMDItemDescription '"Contoso Sales & Marketing $1M Club!"' /path/to/wallpaper.png`. **You must use single and double quotes.**

As written, Wallpappr is designed to be used with Jamf but it can be adapted for other MDM. In fact, the only Jamf-specific commands are the pre-checks (to install swiftDialog, desktoppr, your wallpaper) and the Jamf command while exiting to update the device's inventory information.
