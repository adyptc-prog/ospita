# Ospita

**Room bookings for small guesthouses, with guests booking and cancelling by SMS.**
No server. No internet. No accounts.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Flutter](https://img.shields.io/badge/Flutter-3.10%2B-02569B?logo=flutter)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android)](https://www.android.com)

---

## What is Ospita?

Ospita is an open-source Flutter app for Android that keeps the bookings of a
guesthouse on the phone, one table per room. It also runs an SMS booking bot. A guest texts
`liber`, says how many nights, picks one of the free date ranges and gets the payment details.
The booking appears in the app. Everything runs on the phone, with no server and no internet
connection.

---

## Features

- **Bookings per room** in up to 10 tables, each booking with check-in, check-out, the guest's
  name and up to 3 phone numbers
- **Check-in and check-out hours per day of the week**, and days with no arrivals
- **Free-gap view**, which shows free ranges of at least N nights in the table
- **SMS self-booking:** the guest sends `liber` or `free` (optionally followed by the room's table name),
  replies with the number of nights, then with the number of a date range. `NEXT` shows more dates.
- **24-hour payment deadline:** the bot sends your IBAN. When you mark the booking as paid, the
  guest gets an SMS confirmation. An unpaid SMS booking is cancelled automatically after 24 hours.
- **Cancellation by SMS**: the guest sends `anuleaza` or `cancel`. This works for SMS bookings and for
  bookings added by hand.
- **Alerts and SMS reminders** before each arrival, even with the app closed
- **No-show tracking:** after check-out you confirm whether the guest came. No-shows show up as
  red dots next to the guest, and from a threshold you choose, the bot stops accepting SMS bookings
  from that number.
- **Bot abuse limits**, with a per-number hourly limit, a daily reply limit and a maximum of
  active bookings per number
- **Two-phone sync over SMS**, with messages signed by a pairing code entered on both phones
- **Encrypted backup**, daily and manual, to phone storage or a USB stick
- **Romanian and English**, chosen from the globe icon in the app bar (on first launch: Romanian on a Romanian phone, English otherwise)
- 30-day free trial, then an activation license (see [Free Trial & Activation License](#free-trial--activation-license))

---

## How It Works

```
Guest texts "liber"           →  bot asks how many nights
Guest replies "3"             →  bot replies with free date ranges
Guest replies with a number   →  booking saved, payment deadline and IBAN sent
You mark it paid in the app   →  guest gets an SMS confirmation
```

The SMS bot runs natively on Android (a `BroadcastReceiver`), so it answers even when the
app is closed.
The bot understands the Romanian and the English keywords alike (`liber` / `free`,
`anuleaza` / `cancel`). It replies in the language set in the app on the phone that receives the SMS.

---

## Free Trial & Activation License

The complete source code, including the 30-day trial check, is published here under the AGPL-3.0.
**The code is not sold**, and the rights the AGPL gives you (to use, study, modify and redistribute it)
don't depend on buying anything.

What is sold is an **activation license**: a signed file, tied to one install code (Business ID),
that unlocks the app after the 30-day free trial in the Ospita app distributed by Volt
Academy (the Android APK available at [voltacademy.app/ospita.html](https://voltacademy.app/ospita.html)).

| Period | Requirement |
|---|---|
| First 30 days after install | Free, all features |
| After the trial | Activation license — 30, 60 or 180 days, or permanent |

Licenses are bought at [voltacademy.app/ospita.html](https://voltacademy.app/ospita.html#licentiere),
where current prices are listed. Expirable licenses bought for the same install code add up, and the
license becomes permanent automatically once their total reaches the price of a permanent license.

To activate a license:

1. Open the **Licență** screen in the app and copy the **Cod de instalare** (install code).
2. Buy a license on the site with that code and download `pensiune_license.json`.
3. Back on the **Licență** screen, tap **Selectează fișierul de licență** and pick the downloaded file.

One license covers two synced phones. Once sync is set up, tap **Trimite licența la telefonul partener**
and the license is sent over SMS to the second phone.

Questions about licenses: [voltacademy.app/contact.html](https://voltacademy.app/contact.html)

---

## Platform Support

Ospita is built for **Android** only. SMS sending and receiving, the booking bot,
alarms, backup and license import use Android platform channels (Kotlin, in
`android/app/src/main/kotlin`).

---

## Getting Started

### Requirements
- Flutter SDK 3.10+
- Android SDK (minSdk 24 — Android 7.0)

### Run

```bash
git clone https://github.com/adyptc-prog/ospita.git
cd ospita
flutter pub get
flutter run
```

### Test

```bash
flutter test
dart analyze
cd android && ./gradlew :app:testDebugUnitTest
```

### Build release APK

```bash
flutter build apk --release
```

Release builds are signed with the keystore described in `android/key.properties`, which is not
part of this repository. To build your own release, create that file for your own keystore.

---

## Author

**Adrian Petcu** — [Volt Academy](mailto:adyptc@gmail.com)

---

## Contributing

Pull requests are welcome. For major changes, open an issue first.

All contributions must be compatible with the AGPL-3.0 license.

---

## License

**Ospita — Guesthouse Booking App**<br>
Copyright (C) 2026 Adrian Petcu — Volt Academy

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

The full text of the **GNU Affero General Public License v3.0** is in [LICENSE](LICENSE).

SPDX-License-Identifier: AGPL-3.0-or-later
