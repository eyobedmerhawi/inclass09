import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models/folder.dart';
import 'models/card_record.dart';

class DatabaseHelper {
  // ==================================================
  // DATABASE CONFIGURATION
  // ==================================================

  static const String _databaseName = 'MyDatabase.db';
  static const int _databaseVersion = 2;

  // Activity 08: Original guest table
  static const String table = 'my_table';
  static const String columnId = '_id';
  static const String columnName = 'name';
  static const String columnAge = 'age';

  // Activity 09: New tables
  static const String foldersTable = 'folders';
  static const String cardsTable = 'cards';

  late Database _db;

  // ==================================================
  // INITIALIZE DATABASE
  // ==================================================

  Future<void> init() async {
    final documentsDirectory =
        await getApplicationDocumentsDirectory();

    final path = join(
      documentsDirectory.path,
      _databaseName,
    );

    debugPrint('DATABASE PATH: $path');

    _db = await openDatabase(
      path,
      version: _databaseVersion,

      // Enable foreign-key enforcement.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      // Fresh installation: Create all three tables.
      onCreate: (db, version) async {
        debugPrint('DATABASE onCreate: version $version');

        await _createPartOneTable(db);
        await _createCatalogueTables(db);
      },

      // Existing Activity 08 installation:
      // Preserve my_table and add the new tables.
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint(
          'DATABASE onUpgrade: $oldVersion -> $newVersion',
        );

        if (oldVersion < 2) {
          await _createCatalogueTables(db);
        }
      },
    );

    // ==================================================
    // REPAIR INCOMPLETE VERSION 2 MIGRATION
    // ==================================================
    //
    // Your existing database reports version 2,
    // but the folders and cards tables are missing.
    //
    // This repair creates missing Activity 09 objects
    // without deleting the original guest table.
    //
    // It also checks the index independently.

    await _repairCatalogueSchema();

    // ==================================================
    // DATABASE DIAGNOSTICS
    // ==================================================

    await _printDiagnostics();
  }

  // ==================================================
  // ACTIVITY 08: ORIGINAL TABLE
  // ==================================================

  Future<void> _createPartOneTable(Database db) async {
    await db.execute('''
      CREATE TABLE $table (
        $columnId INTEGER PRIMARY KEY,
        $columnName TEXT NOT NULL,
        $columnAge INTEGER NOT NULL
      )
    ''');
  }

  // ==================================================
  // ACTIVITY 09: CREATE FOLDERS AND CARDS
  // ==================================================

  Future<void> _createCatalogueTables(Database db) async {
    await db.execute('''
      CREATE TABLE $foldersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $cardsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        suit TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        image_ref TEXT,
        folder_id INTEGER NOT NULL,
        FOREIGN KEY (folder_id)
          REFERENCES $foldersTable(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_cards_folder_id
      ON $cardsTable(folder_id)
    ''');
  }

  // ==================================================
  // REPAIR MISSING ACTIVITY 09 TABLES
  // ==================================================

  Future<void> _repairCatalogueSchema() async {
    final existingTables = await _db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name IN ('folders', 'cards')
    ''');

    final tableNames = existingTables
        .map((row) => row['name'] as String)
        .toSet();

    final missingFolders = !tableNames.contains(foldersTable);
    final missingCards = !tableNames.contains(cardsTable);

    final existingIndexes = await _db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
        AND name = 'idx_cards_folder_id'
    ''');

    final missingIndex = existingIndexes.isEmpty;

    if (!missingFolders && !missingCards && !missingIndex) {
      debugPrint('REPAIR: No repair needed.');
      return;
    }

    debugPrint('====================================');
    debugPrint('REPAIR: Incomplete schema detected.');
    debugPrint('Missing folders: $missingFolders');
    debugPrint('Missing cards: $missingCards');
    debugPrint('Missing index: $missingIndex');
    debugPrint('====================================');

    // This transaction is outside onCreate/onUpgrade.
    // It runs only after the database has opened.
    await _db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS $foldersTable (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL
        )
      ''');

      await txn.execute('''
        CREATE TABLE IF NOT EXISTS $cardsTable (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          suit TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          image_ref TEXT,
          folder_id INTEGER NOT NULL,
          FOREIGN KEY (folder_id)
            REFERENCES $foldersTable(id)
            ON DELETE CASCADE
        )
      ''');

      await txn.execute('''
        CREATE INDEX IF NOT EXISTS idx_cards_folder_id
        ON $cardsTable(folder_id)
      ''');
    });

    debugPrint('REPAIR: Activity 09 schema repair completed.');
  }

  // ==================================================
  // DATABASE DIAGNOSTICS
  // ==================================================

  Future<void> _printDiagnostics() async {
    try {
      final version = await _db.rawQuery(
        'PRAGMA user_version',
      );

      final tables = await _db.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        ORDER BY name
      ''');

      final foreignKeys = await _db.rawQuery(
        'PRAGMA foreign_keys',
      );

      final cardForeignKeys = await _db.rawQuery(
        'PRAGMA foreign_key_list(cards)',
      );

      final cardIndexes = await _db.rawQuery(
        'PRAGMA index_list(cards)',
      );

      final guestRows = await queryAllRows();
      final guestCount = await queryRowCount();

      debugPrint('====================================');
      debugPrint('ACTIVITY 09 DATABASE DIAGNOSTICS');
      debugPrint('DATABASE VERSION: $version');
      debugPrint('DATABASE TABLES: $tables');
      debugPrint('FOREIGN KEYS: $foreignKeys');
      debugPrint('CARD FOREIGN KEYS: $cardForeignKeys');
      debugPrint('CARD INDEXES: $cardIndexes');
      debugPrint('ORIGINAL GUEST COUNT: $guestCount');
      debugPrint('ORIGINAL GUEST ROWS: $guestRows');
      debugPrint('====================================');
    } catch (error, stackTrace) {
      debugPrint(
        'DATABASE DIAGNOSTIC ERROR: $error\n$stackTrace',
      );
    }
  }

  // ==================================================
  // ACTIVITY 08: GUEST CRUD
  // ==================================================

  Future<int> insert(Map<String, dynamic> row) async {
    return await _db.insert(
      table,
      row,
    );
  }

  Future<List<Map<String, dynamic>>> queryAllRows() async {
    return await _db.query(
      table,
      orderBy: '$columnId ASC',
    );
  }

  Future<int> queryRowCount() async {
    final results = await _db.rawQuery(
      'SELECT COUNT(*) FROM $table',
    );

    return Sqflite.firstIntValue(results) ?? 0;
  }

  Future<int> update(Map<String, dynamic> row) async {
    final int id = row[columnId];

    return await _db.update(
      table,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    return await _db.delete(
      table,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  // ==================================================
  // ACTIVITY 09: FOLDER CRUD
  // ==================================================

  Future<int> insertFolder(Folder folder) async {
    return await _db.insert(
      foldersTable,
      folder.toMap(),
    );
  }

  Future<List<Folder>> getFoldersWithCounts() async {
    final rows = await _db.rawQuery('''
      SELECT
        folders.id,
        folders.name,
        folders.created_at,
        COUNT(cards.id) AS card_count
      FROM folders
      LEFT JOIN cards
        ON cards.folder_id = folders.id
      GROUP BY
        folders.id,
        folders.name,
        folders.created_at
      ORDER BY folders.name COLLATE NOCASE ASC
    ''');

    return rows
        .map((row) => Folder.fromMap(row))
        .toList();
  }

  Future<int> deleteFolder(int id) async {
    return await _db.delete(
      foldersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================================================
  // ACTIVITY 09: CARD CRUD
  // ==================================================

  Future<List<CardRecord>> getCards(int folderId) async {
    final rows = await _db.query(
      cardsTable,
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );

    return rows
        .map((row) => CardRecord.fromMap(row))
        .toList();
  }

  Future<int> insertCard(CardRecord card) async {
    return await _db.insert(
      cardsTable,
      card.toMap(),
    );
  }

  Future<int> updateCard(CardRecord card) async {
    if (card.id == null) {
      throw ArgumentError(
        'Cannot update a card without an ID.',
      );
    }

    return await _db.update(
      cardsTable,
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<int> deleteCard(int id) async {
    return await _db.delete(
      cardsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================================================
  // ACTIVITY 09: DIAGNOSTIC HELPER METHODS
  // ==================================================

  Future<int> getDatabaseVersion() async {
    final result = await _db.rawQuery(
      'PRAGMA user_version',
    );

    return result.first['user_version'] as int;
  }

  Future<int> getForeignKeysEnabled() async {
    final result = await _db.rawQuery(
      'PRAGMA foreign_keys',
    );

    return result.first['foreign_keys'] as int;
  }

  Future<List<Map<String, dynamic>>> getCardForeignKeys() async {
    return await _db.rawQuery(
      'PRAGMA foreign_key_list(cards)',
    );
  }

  Future<List<Map<String, dynamic>>> getCardIndexes() async {
    return await _db.rawQuery(
      'PRAGMA index_list(cards)',
    );
  }
}