import 'package:flutter/material.dart';

import 'database_helper.dart';
import 'models/folder.dart';
import 'models/card_record.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final helper = DatabaseHelper();

  try {
    await helper.init();
    runApp(CatalogueApp(helper: helper));
  } catch (error, stackTrace) {
    debugPrint('Database initialization failed: $error\n$stackTrace');

    runApp(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Database Error')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Could not open the database. Check the debug logs.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CatalogueApp extends StatelessWidget {
  final DatabaseHelper helper;

  const CatalogueApp({super.key, required this.helper});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Catalogue',
      debugShowCheckedModeBanner: false,
      home: FolderScreen(helper: helper),
    );
  }
}

class FolderScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const FolderScreen({super.key, required this.helper});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Folder> _folders = [];
  bool _busy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _loading = true;
      _error = null;
    });

    try {
      final folders = await widget.helper.getFoldersWithCounts();

      if (!mounted) return;

      setState(() {
        _folders = folders;
      });
    } catch (error, stackTrace) {
      debugPrint('Folder read failed: $error\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _error = 'Could not load folders. Tap Refresh to retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _addFolder() async {
    if (_busy) return;

    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Folder'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Folder name',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a folder name.';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    // Dispose after the dialog finishes its exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();

    if (!mounted || name == null || _busy) return;

    setState(() => _busy = true);

    try {
      final id = await widget.helper.insertFolder(
        Folder(
          name: name,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      if (!mounted) return;

      _showMessage('Created folder "$name" (ID $id).');
    } catch (error, stackTrace) {
      debugPrint('Folder insert failed: $error\n$stackTrace');

      if (!mounted) return;

      _showMessage(
        'Could not create "$name". Check whether the name already exists.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    if (_busy || folder.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Folder?'),
        content: Text(
          'Delete "${folder.name}" and all ${folder.cardCount} cards inside it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true || _busy) return;

    setState(() => _busy = true);

    try {
      final affected = await widget.helper.deleteFolder(folder.id!);

      if (!mounted) return;

      _showMessage(
        affected == 1
            ? 'Deleted "${folder.name}" and its cards.'
            : 'Folder no longer exists ($affected rows).',
      );
    } catch (error, stackTrace) {
      debugPrint('Folder delete failed: $error\n$stackTrace');

      if (!mounted) return;

      _showMessage('Could not delete folder.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Catalogue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addFolder,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('Add Folder'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _folders.isEmpty
                  ? const Center(child: Text('No folders yet. Add one!'))
                  : ListView.builder(
                      itemCount: _folders.length,
                      itemBuilder: (context, index) {
                        final folder = _folders[index];

                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text(folder.name),
                            subtitle: Text(
                              'ID: ${folder.id} · ${folder.cardCount} cards',
                            ),
                            onTap: _busy
                                ? null
                                : () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CardScreen(
                                          helper: widget.helper,
                                          folder: folder,
                                        ),
                                      ),
                                    );

                                    if (mounted) await _refresh();
                                  },
                            trailing: IconButton(
                              tooltip: 'Delete ${folder.name}',
                              onPressed: _busy
                                  ? null
                                  : () => _deleteFolder(folder),
                              icon: const Icon(Icons.delete),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class CardScreen extends StatefulWidget {
  final DatabaseHelper helper;
  final Folder folder;

  const CardScreen({
    super.key,
    required this.helper,
    required this.folder,
  });

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  List<CardRecord> _cards = [];
  bool _busy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _loading = true;
      _error = null;
    });

    try {
      final cards = await widget.helper.getCards(widget.folder.id!);

      if (!mounted) return;

      setState(() => _cards = cards);
    } catch (error, stackTrace) {
      debugPrint('Card read failed: $error\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _error = 'Could not load cards. Tap Refresh to retry.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCardForm({CardRecord? existing}) async {
    if (_busy) return;

    final result = await Navigator.push<CardRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => CardFormScreen(
          folderId: widget.folder.id!,
          existing: existing,
        ),
      ),
    );

    if (!mounted || result == null || _busy) return;

    setState(() => _busy = true);

    try {
      if (existing == null) {
        final id = await widget.helper.insertCard(result);
        if (!mounted) return;
        _showMessage('Added card ID $id.');
      } else {
        final affected = await widget.helper.updateCard(result);
        if (!mounted) return;
        _showMessage(
          affected == 1
              ? 'Updated card ID ${existing.id} (1 row).'
              : 'Card ID ${existing.id} was not found.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Card save failed: $error\n$stackTrace');

      if (!mounted) return;
      _showMessage('Could not save card. Check the logs.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  Future<void> _deleteCard(CardRecord card) async {
    if (_busy || card.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Card?'),
        content: Text('Delete "${card.title}" (ID ${card.id})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true || _busy) return;

    setState(() => _busy = true);

    try {
      final affected = await widget.helper.deleteCard(card.id!);

      if (!mounted) return;

      _showMessage(
        affected == 1
            ? 'Deleted card ID ${card.id} (1 row).'
            : 'Card ID ${card.id} was not found.',
      );
    } catch (error, stackTrace) {
      debugPrint('Card delete failed: $error\n$stackTrace');

      if (!mounted) return;
      _showMessage('Could not delete card.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _suitSymbol(String suit) {
    switch (suit) {
      case 'Hearts':
        return '♥';
      case 'Diamonds':
        return '♦';
      case 'Clubs':
        return '♣';
      case 'Spades':
        return '♠';
      default:
        return '🂠';
    }
  }

  Widget _cardImage(CardRecord card) {
    final ref = card.imageRef;

    if (ref == null || ref.trim().isEmpty) {
      return Text(
        _suitSymbol(card.suit),
        style: const TextStyle(fontSize: 30),
      );
    }

    if (ref.startsWith('https://') || ref.startsWith('http://')) {
      return Image.network(
        ref,
        width: 44,
        height: 44,
        errorBuilder: (_, _, _) => Text(
          _suitSymbol(card.suit),
          style: const TextStyle(fontSize: 30),
        ),
      );
    }

    return Text(
      _suitSymbol(card.suit),
      style: const TextStyle(fontSize: 30),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.name),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openCardForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Card'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _cards.isEmpty
                  ? const Center(child: Text('No cards in this folder yet.'))
                  : ListView.builder(
                      itemCount: _cards.length,
                      itemBuilder: (context, index) {
                        final card = _cards[index];

                        return Card(
                          child: ListTile(
                            leading: _cardImage(card),
                            title: Text(card.title),
                            subtitle: Text(
                              'ID: ${card.id} · ${card.suit}\n${card.notes}',
                            ),
                            isThreeLine: card.notes.isNotEmpty,
                            onTap: _busy
                                ? null
                                : () => _openCardForm(existing: card),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit ${card.title}',
                                  onPressed: _busy
                                      ? null
                                      : () => _openCardForm(existing: card),
                                  icon: const Icon(Icons.edit),
                                ),
                                IconButton(
                                  tooltip: 'Delete ${card.title}',
                                  onPressed: _busy
                                      ? null
                                      : () => _deleteCard(card),
                                  icon: const Icon(Icons.delete),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class CardFormScreen extends StatefulWidget {
  final int folderId;
  final CardRecord? existing;

  const CardFormScreen({
    super.key,
    required this.folderId,
    this.existing,
  });

  @override
  State<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends State<CardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageController;

  String _suit = 'Hearts';

  static const _suits = [
    'Hearts',
    'Diamonds',
    'Clubs',
    'Spades',
  ];

  @override
  void initState() {
    super.initState();

    final card = widget.existing;

    _titleController = TextEditingController(text: card?.title ?? '');
    _notesController = TextEditingController(text: card?.notes ?? '');
    _imageController = TextEditingController(text: card?.imageRef ?? '');
    _suit = card?.suit ?? 'Hearts';
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final imageRef = _imageController.text.trim();

    Navigator.pop(
      context,
      CardRecord(
        id: widget.existing?.id,
        title: _titleController.text.trim(),
        suit: _suit,
        notes: _notesController.text.trim(),
        imageRef: imageRef.isEmpty ? null : imageRef,
        folderId: widget.folderId,
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add Card' : 'Edit Card'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Card title',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a card title.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _suit,
                  decoration: const InputDecoration(
                    labelText: 'Suit',
                    border: OutlineInputBorder(),
                  ),
                  items: _suits
                      .map(
                        (suit) => DropdownMenuItem(
                          value: suit,
                          child: Text(suit),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _suit = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imageController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _save,
                  child: Text(
                    widget.existing == null ? 'Add Card' : 'Save Changes',
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}