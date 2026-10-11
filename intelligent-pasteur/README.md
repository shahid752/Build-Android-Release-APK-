# CampusSchedule 🎓

A complete, production-ready Flutter mobile application for university students to import their timetable from PDF documents or web portal sessions, store the schedule offline in a local SQLite database, view daily and weekly classes, and receive exact high-importance push notifications 5–15 minutes before every lecture with room and hall details.

---

## 🚀 Key Features

1. **📄 PDF Timetable Extraction & Parsing**:
   - Extracts tabular course schedules directly from university PDF files using `syncfusion_flutter_pdf`.
   - Heuristic & regex parsing engine supporting multiple formats (pipe, tab, CSV, unstructured timetable text).
   - "Demo Sample" button for one-tap demo loading and verification.

2. **🌐 Student Portal Web Scraper**:
   - Embedded `flutter_inappwebview` allowing students to navigate directly to their university student portal, log in securely, and scrape DOM table nodes into schedule items.

3. **💾 Offline SQLite Persistence**:
   - Fast, local offline timetable storage using `sqflite` with indexed queries and transaction-backed batch inserts.

4. **🔔 Exact Local Push Notifications**:
   - Uses `flutter_local_notifications` with `AndroidScheduleMode.exactAllowWhileIdle` and timezone matching (`timezone` + `flutter_timezone`).
   - Repeats weekly on the exact day of the week and start time minus the chosen lead time (5, 10, or 15 minutes).
   - Prominently displays Course Title, Instructor, and exact Room/Hall location.

5. **📱 Modern Material 3 UI**:
   - Weekday Tab Bar (Monday–Friday) with active day auto-selection.
   - Dynamic Next Lecture countdown alert banner.
   - Lecture cards with color badges, time stamps, and prominent location tags (`Block A, Room 204`).
   - Settings for notification toggle, lead time customization, test notification triggers, and database diagnostics.

---

## 📦 Project Structure

```
campus_schedule/
├── android/
│   └── app/src/main/AndroidManifest.xml   # Exact alarms & notification permissions
├── lib/
│   ├── main.dart                          # App entrypoint & theme setup
│   ├── models/
│   │   └── class_session.dart             # ClassSession data model & helpers
│   ├── services/
│   │   ├── database_service.dart          # SQLite CRUD helper
│   │   ├── notification_service.dart      # Exact alarm & notification manager
│   │   └── timetable_parser.dart          # PDF text extraction & regex parser
│   ├── screens/
│   │   ├── home_screen.dart               # Weekday tabs & lecture list
│   │   ├── import_screen.dart             # PDF file picker & preview
│   │   ├── web_portal_import_screen.dart  # In-App WebView scraper
│   │   └── settings_screen.dart           # Lead time & alarm preferences
│   └── widgets/
│       ├── lecture_card.dart              # Course card with location pill
│       └── day_schedule_view.dart         # Daily lecture list & empty states
├── test/
│   └── timetable_test.dart                # Unit tests
└── pubspec.yaml                           # Dependency manifest
```

---

## 🛠️ Android & iOS Setup Notes

### Android Manifest Permissions (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```
Scheduled notification receivers (`ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver`) are declared to maintain alarms across device restarts.
