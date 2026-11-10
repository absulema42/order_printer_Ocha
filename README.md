# O'Cha Thai Order Printer

A Flutter app for taking O'Cha Thai's orders and printing them on a SUNMI NT311
(or any ESC/POS network receipt printer) over Wi-Fi. One codebase runs on
Android, Windows and Linux.

## Features

- Menu grid with category filters; tap an item to add it
- Eat in / Takeaway / Delivery, with table number or customer name
- Quantities and per-item notes, with one-tap chips for protein, spice level and dietary needs
- Large, easy-to-read kitchen slips with order number (restarts daily), time and total
- Settings: printer IP and port, copies per order, show/hide prices, test print
- Payment method on each order (Card / Cash / Online / Unpaid), printed on the slip
- Sales history and reports (chart icon on the main screen), see below
- Thai menu built in (prices are placeholders); edit, add or remove items in Settings → Edit menu

## 1. Install Flutter on Arch

```bash
sudo pacman -S git clang cmake ninja pkgconf gtk3 unzip
yay -S flutter-bin          # or any AUR helper; or install from flutter.dev
flutter doctor
```

For Android builds you'll also need Android Studio (AUR: `android-studio`),
then run `flutter doctor --android-licenses`.

## 2. Set up the project (once)

```bash
cd order_printer
chmod +x setup.sh
./setup.sh
```

Already set up the earlier version? Just run `dart run tool/apply_branding.dart`
to set the app name, then `flutter run -d linux`. The old sample menu is swapped for
the Thai one automatically (a menu you edited yourself is kept).

## 3. Run it on your laptop

```bash
flutter run -d linux
```

Open **Settings**, enter the printer's IP address, tap **Print test page**,
then go back and take an order.

## 4. Build for other devices

| Target  | Command                         | Output |
|---------|---------------------------------|--------|
| Android | `flutter build apk --release`   | `build/app/outputs/flutter-apk/app-release.apk` |
| Windows | `flutter build windows`         | `build/windows/x64/runner/Release/` (must be built on a Windows PC) |
| Linux   | `flutter build linux --release` | `build/linux/x64/release/bundle/` |

Copy the APK to an Android phone or tablet and open it to install
(allow "install unknown apps" when asked).

## Android tablet (e.g. Samsung Galaxy Tab A9)

You get **OChaThai.apk**. In landscape the menu and the order sit side by
side; in portrait the order opens from the bottom.

### Make the APK

- **GitHub (easiest):** upload the project as described under *Windows
  program*, Option A. Download **OChaThai-Android** from the finished run.
- **Windows PC:** install Flutter, then Android Studio
  (https://developer.android.com/studio). Open Android Studio once and let it
  finish installing the Android SDK, then run `flutter doctor --android-licenses`
  and accept. Double-click **build_android.bat**. The APK is `dist\OChaThai.apk`.
- **Linux:** same, with `./build_android.sh`.

### Install on the tablet

1. Copy OChaThai.apk to the tablet (USB cable, Google Drive, or email it
   to yourself).
2. Open it from **My Files** (Downloads) or the email/Drive app.
3. When Android says the app can't install unknown apps, tap **Settings**,
   switch on **Allow from this source**, go back and tap **Install**.
4. If Play Protect warns about an unknown app, tap **More details → Install
   anyway**.
5. Open O'Cha Thai, go to Settings, enter the printer's IP address and tap
   **Print test page**. The tablet must be on the same Wi-Fi as the printer.

### Updates keep your data

Every build is signed with the same key (`android_signing/ocha.keystore`,
applied by `tool/use_signing_key.dart`), so a new APK installs over the old
one and keeps the menu, settings and sales history. Keep that file safe and
don't delete it. Without it, updates would need the app to be uninstalled
first, which erases the data on the tablet.

### Tips for using it as a till

- Settings → Display → **Screen timeout**: set it longer so the screen
  doesn't lock between orders.
- Export the sales spreadsheets regularly (download icon on the Sales
  screen) as a backup.

## Windows program

You get **OChaThai-Setup.exe**, a normal Windows installer that adds
O'Cha Thai to the Start menu and (optionally) the desktop. There's also a
portable zip that runs without installing. Two ways to make it:

### Option A: let GitHub build it (no software to install)

1. Create a free account at github.com and make a new **private** repository.
2. On the repository page choose **Add file → Upload files**, drag in
   everything inside this `order_printer` folder (including the hidden
   `.github` folder, so upload the folder contents, not the zip), and commit.
3. Open the **Actions** tab. The "Build apps" run starts by itself (or press
   **Run workflow**). It takes about 10 minutes.
4. Open the finished run and download **OChaThai-Windows** (installer +
   portable zip) and **OChaThai-Android** (APK) from *Artifacts*.

Each time you upload changes, new builds are made.

### Option B: build on a Windows PC

1. Install Flutter: https://docs.flutter.dev/get-started/install/windows
2. Install Visual Studio 2022 Community with **Desktop development with C++**.
3. Optional: install Inno Setup 6 (https://jrsoftware.org/isinfo.php) to get
   the Setup.exe as well as the portable zip.
4. Double-click **build_windows.bat**. Results are in the `dist` folder.

To just try it on a Windows PC with Flutter installed, double-click
**setup.bat**.

### Notes

- Windows may show "Windows protected your PC" the first time because the
  installer isn't signed. Click **More info → Run anyway**.
- Allow the app through the firewall if Windows asks. It needs your local
  network to reach the printer.
- Settings, menu and sales history are stored in the Windows user profile
  (AppData) and are kept when you update or reinstall. Exported sales
  spreadsheets go to Documents\OCha Thai Sales.

## Menu

The O'Cha menu (151 items from O_cha_menu.xlsx) is built in. Open
**Settings → Edit menu** to:

- **Add, edit or remove** items by hand: number, name, category, price and
  an optional takeaway price.
- **Import Excel**: pick an .xlsx (or .csv) file. You'll see what was found,
  then choose **Replace menu** or **Add & update** (same category + name gets
  the new price, new items are added, nothing is removed).

Spreadsheet layouts the importer understands:

1. Sections, like O_cha_menu.xlsx: a header row `Item No | Starters | Price`
   then the items; the next header (`Item No | Soup | Price`) starts a new
   category. Add a `Take Away Price` column for a different takeaway price.
   Items without a number share the number above (e.g. Tom Yum variants).
2. One table: `Item No | Name | Category | Price | Take Away Price`.

On Linux the file chooser needs zenity: `sudo pacman -S zenity`.

On the order screen, search by name or menu number. Takeaway and Delivery
orders use the takeaway price where there is one.

## Receipts

Each order prints a customer receipt in the same layout as the till
receipt: restaurant name, business line, email, order details with staff and
device, a product table (price, qty, total), Sub Total / Total / Amount Due,
the VAT breakdown (rate, percentage, tax) and VAT number, and a thank-you
message. All of these are editable in **Settings → Receipt**. Prices include
VAT, so the VAT shown is the part of the total that is VAT (total × 20/120).

"Print for each order" in Settings switches between the customer receipt,
the large kitchen ticket, or both.

## Sales & reports

Every order is saved on the device when it prints. Tap the **chart icon**
on the main screen to see:

- Today, yesterday, this/last week, this/last month, or any dates you choose
- Total sales, orders, average order, items sold
- Net sales and VAT (rate set in Settings; 0 if not VAT registered)
- Breakdowns by payment method, order type, hour or day, category and item
- **Orders** tab: every order, tap one to change how it was paid, reprint
  it, or void it (voided orders stay listed but are left out of totals)
- **Print icon**: prints the report on the receipt printer (end-of-day / Z report)
- **Download icon**: exports three spreadsheets (summary, orders, items) as
  CSV for Excel or your accountant. On Windows/Linux they go to
  Documents/OCha Thai Sales; on Android the share menu opens so you can
  email them or save to Drive.

History is stored per device. If you take orders on more than one device,
each keeps its own history; export from each, or use one main device.

## Files

- `lib/screens/order_screen.dart` – the order screen
- `lib/screens/settings_screen.dart` – printer settings and test print
- `lib/screens/menu_editor_screen.dart` – menu editing
- `lib/screens/sales_screen.dart` – sales history and reports
- `lib/sales.dart` – saving orders to history
- `lib/reports.dart` – report calculations and spreadsheet export
- `lib/ticket.dart` – layout of the printed slips and report
- `lib/escpos.dart` – printer commands
- `lib/printer_service.dart` – sends the slip to the printer over TCP port 9100

## Troubleshooting

- **"Could not reach the printer"**: check the device is on the same Wi-Fi as
  the printer and the IP hasn't changed (reserve it in your router).
- **£ prints as another character**: the printer's code page differs; change
  `0x9C` for '£' in `lib/escpos.dart`, or replace '£' in `formatPrice`.
