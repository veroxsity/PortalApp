# PortalApp

PortalApp installs and manages apps on an Xbox in Developer Mode from a Windows PC or an Android phone. It talks to the console's built-in Device Portal over your home network, so nothing has to be installed on the console.

## Download

Builds for Windows and Android are on the [releases page](../../releases). On Windows, unzip the folder and run `PortalApp.exe`. On Android, open the APK and allow installs from the app you opened it with. It needs Windows 10 or later, or Android 7 or later.

## Connecting

Turn on Developer Mode on the console and open Dev Home, which shows the console's IP address. Type that into PortalApp on a device that is on the same network. If you set a username and password for the Device Portal, switch on Portal sign-in and enter them too. The last few addresses are remembered. Passwords are not.

## Installing and updating apps

The Store tab lists the apps from three stores: [Raccoon Dev Store](https://veroxsity.github.io/RaccoonDevStore/), [Emulation Revival](https://emulationrevival.github.io/) and the older [Xbox Dev Store](https://xboxdevstore.github.io/). An app that is in more than one store is shown once, and its page lets you choose which store to install from. Each store has a switch on the Console tab. Pressing Install on an app downloads the package, checks it against the SHA-256 the listing publishes (when it has one) and sends it to the console. When the store has a newer version of something you already have, the Installed tab shows a badge. An update goes over the top of the installed copy, so the app keeps its saved data.

Some listings only link to a MediaFire page or a GitHub release, and PortalApp finds the real file when you press Install. A zip or 7z is unpacked and every package inside it is sent, with Microsoft's frameworks first. An app with several builds, like RetroArch, lets you choose which one to install. A listing that needs clicking through opens in a built-in browser that blocks ads and popups, and when a page starts downloading an app package the browser closes and the install carries on. A direct download link opens in your normal browser.

A package you already have can be installed from the Console tab. The console only accepts signed packages and PortalApp does not sign anything, so an unsigned one is refused.

## Managing apps

Tapping an app in the Installed tab opens it. From there it can be launched, closed or deleted. Deleting also removes the app's saved data. The Files button opens its data folders, where files can be downloaded, uploaded and deleted and new folders made. The Console tab can show what the console is displaying right now.

## Where the listings come from

Emulation Revival's list is read from the JSON catalogue its own site is built from, and Raccoon Dev Store's from its catalogue. The Xbox Dev Store has no feed, so its page is read directly. PortalApp only links to the original developers' downloads and does not host or change any package. Tools for a PC or a phone are left out of the lists. PortalApp is not affiliated with these stores or with the developers of the apps in them.

## Building

`flutter build windows` and `flutter build apk` make the two builds. The Windows build needs the Visual Studio C++ workload and NuGet on the PATH, because the browser plugin downloads Microsoft's WebView2 SDK while it builds. Running it needs the WebView2 runtime, which Windows 11 and current Windows 10 already have.

## Licence

MIT, see [LICENSE](LICENSE). The font is Karla, under the SIL Open Font License. The Windows build also ships Microsoft's WebView2 loader, the Windows Implementation Library and nlohmann/json, under BSD and MIT licences. PortalApp is not affiliated with Microsoft or Xbox.
