# In-Class Activity 08 — Local Storage Lab

## Fall Festival Roster

This Flutter application uses SQLite to store a roster of festival guests locally. Users can add, view, edit, and delete guests. Each guest has a unique database ID, name, and age.

## Technologies
- Flutter and Dart
- SQLite (`sqflite`)
- `path_provider` and `path`

## Features
- Add a guest with a name and age
- Display saved guests and record count
- Edit a guest using their unique ID
- Delete a guest after confirmation
- Refresh the roster
- Validate names and ages (0–130)
- Preserve records after closing and reopening the app

## Manual Test Log

| Test | Action / Input | Expected Result | Observed Result | Status |
|---|---|---|---|---|
| T1 | Refresh empty roster | Count 0, empty message | Empty roster displayed | Pass |
| T2 | Add River (21), River (34) | Two unique IDs, count 2 | IDs 1 and 2, count 2 | Pass |
| T3 | Edit ID 2 to 99 and cancel; edit again to 35 and save | Cancel preserves 34; save changes only ID 2 | ID 1 stayed 21; ID 2 became 35; count 2 | Pass |
| T4 | Fully stop and relaunch app | Same records and IDs persist | IDs 1 and 2 remained, ages 21 and 35; count 2 | Pass |
| T5 | Cancel deletion of ID 1, then confirm deletion | Cancel changes nothing; confirm removes one row | ID 1 deleted; ID 2 remained; count 1 | Pass |
| T6 | Reject blank name and invalid ages; add Acorn (0), Oak (130) | Invalid inputs rejected; valid boundary ages accepted | Invalid `abc` age rejected; final IDs 2, 3, 4; count 3 | Pass for observed checks; confirm other invalid inputs |

## Final Database Records

| ID | Name | Age |
|---|---|---|
| 2 | River | 35 |
| 3 | Acorn | 0 |
| 4 | Oak | 130 |

## Reflection 1 — Persistence

Before restarting the app, I predicted that the two River records would still be there because SQLite saves them locally. After completely stopping and reopening the app, both records were still present with their original IDs and ages. The database helper opens `MyDatabase.db`, and the app queries the saved records again when it starts.

## Reflection 2 — Unique IDs

I added two guests with the same name, River, so using names to identify records would not be reliable. SQLite assigned IDs 1 and 2, allowing me to update only the second River from age 34 to 35. The update affected one row, and the first River remained unchanged at age 21.

## Reflection 3 — Usability and Validation

The validation messages helped me understand why an input was rejected. For example, entering `abc` as an age displayed a whole-number validation error without changing the record count. One improvement I would make is clearing the previous success message when a new form submission fails, so the feedback is less confusing, although that would require a little more UI state handling.

## Evidence

- `evidence/T4_before.png` — Records before restarting
- `evidence/T4_after.png` — Records after restarting
- `evidence/T6_invalid.png` — Invalid age validation
- `evidence/analysis_output.txt` — Flutter static analysis

## Run Instructions

```bash
flutter pub get
flutter run
```

Run the application on an Android device or emulator with SQLite support.