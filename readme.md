<h1 align="center">EVERYTHING</h1>

<p align="center">
  a dynamic island, a scratchpad, a radial menu and instant spaces for your mac. one tiny app.
</p>

<p align="center">
  <a href="https://github.com/shvm-mane/everything/releases/latest"><b>download the dmg</b></a>
</p>

<p align="center">
  <img src="docs/screenshots/demo.gif" width="720" alt="EVERYTHING's island opening, switching between the scratchpad and claude usage, then closing">
</p>

---

hey. this is my mac utility. i used to run three apps
([vorssaint](https://github.com/vorssaint/vorssaint-utils),
[wisp](https://github.com/sulemaanhamza/wisp) and
[instantspaceswitcher](https://github.com/jurplel/InstantSpaceSwitcher))
and wanted one app that does only the bits i actually use, the way i like them.
so i forked them into one and cut everything else.

it's opinionated and tailored to me: no feature buffet, no menu bar icon, very few settings.
if that sounds like you too, grab it.

## what it does

**dynamic island.** click the notch for an apple music player. volume, brightness, battery
and song changes show up around the notch. two pills float beside the open island: scratchpad
on the left, claude on the right.

<p align="center"><img src="docs/screenshots/player.png" width="560" alt="the island's apple music player with its two side pills"></p>

**scratchpad.** a markdown note that lives in the island (it's [wisp](https://github.com/sulemaanhamza/wisp) under the hood).
headings, lists, checkboxes, history, saved notes. open it with ⌥space from anywhere.

<p align="center"><img src="docs/screenshots/scratchpad.png" width="560" alt="the scratchpad open in the island"></p>

**claude pro usage.** your session and weekly limits, read straight from claude code on your mac.
while claude code is working, a little spinner and timer sit next to the notch, and you get a
notice when it's done. no sign-in, no api key.

<p align="center"><img src="docs/screenshots/claude.png" width="560" alt="claude pro session and weekly usage in the island"></p>

**radial menu.** tap the trackpad with five fingers and a wheel opens at your pointer: files,
folders, websites (it grabs their icons), the color picker, and submenus.

<p align="center"><img src="docs/screenshots/radial.png" width="300" alt="the radial menu with the color picker highlighted"></p>

**instant spaces.** switch desktops with no slide animation, with keybinds (⌃⌥⌘← / ⌃⌥⌘→ by default, change them
in settings) or the normal trackpad swipe. that's [instantspaceswitcher](https://github.com/jurplel/InstantSpaceSwitcher).

**color picker.** click any pixel on screen and its color is copied as hex, rgb, hsl or swiftui.

**small extras.** the volume and brightness keys show the island's own hud, and opening a `.dmg`
offers to install the app inside and eject it.

## install

1. download `EVERYTHING.dmg` from [releases](https://github.com/shvm-mane/everything/releases/latest).
2. drag EVERYTHING into applications.
3. the app isn't notarized (that needs a paid apple developer account), so macos will complain the
   first time. right-click EVERYTHING in applications → **open** → **open**. or, in terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/EVERYTHING.app
   ```
4. settings opens on first launch. grant what you want to use; each permission says what it's for.

there's no menu bar icon. to get back to settings, open EVERYTHING again (from finder,
spotlight or raycast). ⌘q quits while settings is open.

**needs:** macos 14 or newer. the island is built for macs with a notch, and the radial menu's
tap needs a trackpad.

## permissions

| permission | why |
|---|---|
| accessibility | keybinds, instant spaces, the radial menu's tap, the volume keys |
| automation (music) | controlling apple music from the island |
| screen recording | the color picker's magnifier |

everything runs locally. EVERYTHING doesn't phone home; the only network request it makes is
fetching a website's icon when you add a link to the radial menu, and that goes to the
website itself.

## settings

<p align="center">
  <img src="docs/screenshots/settings-general.png" width="420" alt="EVERYTHING settings, general page">
  <img src="docs/screenshots/settings-radial.png" width="420" alt="EVERYTHING settings, radial menu page">
</p>

## build it yourself

you need macos 14+ and xcode or the command line tools.

```sh
git clone https://github.com/shvm-mane/everything.git
cd everything
./scripts/build-app.sh --install   # builds, installs to /Applications and launches
./scripts/build-app.sh --dmg       # builds build/EVERYTHING.dmg
./scripts/build-app.sh check       # quick debug compile
```

the script signs with your apple development identity if you have one (so permission grants
survive rebuilds), otherwise ad hoc.

small dev thing: posting the distributed notification `com.shvmane.everything.radialMenu`
opens the radial menu at the pointer, handy for testing without five fingers.

## credits

EVERYTHING is a fork of, and wouldn't exist without:

- **[vorssaint](https://github.com/vorssaint/vorssaint-utils)** by vorssaint (gpl-3.0): the dynamic island, radial menu, color picker and most of the app.
- **[wisp](https://github.com/sulemaanhamza/wisp)** by sulemaan hamza (mit): the scratchpad editor. license in `Sources/Everything/Scratchpad/Wisp/LICENSE-wisp.txt`.
- **[instantspaceswitcher](https://github.com/jurplel/InstantSpaceSwitcher)** by jurplel (mit): instant space switching. license in `Sources/ISS/LICENSE-InstantSpaceSwitcher.txt`.

go star them.

## license

because it's built on vorssaint, EVERYTHING is [gpl-3.0-or-later](LICENSE).
