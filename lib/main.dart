import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// ================================
// ======= CONFIG / BACKEND =======
// ================================
// IMPORTANT: BigCommerce credentials MUST NOT live in the app.
// Create a tiny server-side proxy (e.g., /api) that holds the BC token
// and forwards requests. Point baseUrl below to that proxy.
const String baseUrl = 'http://10.0.2.2/api'; // <-- change to your proxy origin

class ApiClient {
  final http.Client _client;
  ApiClient([http.Client? client]) : _client = client ?? http.Client();

  Future<List<ProductSuggestion>> searchProducts(String query, {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse('$baseUrl/catalog/products').replace(queryParameters: {
      'name:like': query,
      'limit': '$limit',
    });
    final resp = await _client.get(uri, headers: {"Accept": "application/json"});
    if (resp.statusCode != 200) return [];
    final jsonBody = json.decode(resp.body);
    final List data = (jsonBody is Map<String, dynamic>) ? (jsonBody['data'] ?? []) : (jsonBody as List? ?? []);
    return data.map((p) => ProductSuggestion.fromJson(p as Map<String, dynamic>)).toList();
  }
}

// ================================
// ============ APP ===============
// ================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hot Melt Supply',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF003366)),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hot Melt Supply')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Customer Tools', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () => launchUrl(Uri.parse('https://www.hotmeltsupplyco.com')),
                child: const Text('Shop Store'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LineAuditHomePage())),
                child: const Text('Line Audit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================
// ======= LINE AUDIT HOME ========
// ================================
class LineAuditHomePage extends StatefulWidget {
  const LineAuditHomePage({super.key});
  @override
  State<LineAuditHomePage> createState() => _LineAuditHomePageState();
}

class _LineAuditHomePageState extends State<LineAuditHomePage> {
  List<String> savedLineNames = [];

  @override
  void initState() {
    super.initState();
    _loadSavedLines();
  }

  Future<void> _loadSavedLines() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final filtered = keys.where((k) => k.startsWith('line_audit_')).toList();
    setState(() {
      savedLineNames = filtered.map((k) => k.replaceFirst('line_audit_', '')).toList();
      savedLineNames.sort();
    });
  }

  void _showSavedLines(BuildContext context, {required bool isEdit}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'Select Line to Edit' : 'Select Line to Open'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: savedLineNames.length,
            itemBuilder: (context, i) {
              final name = savedLineNames[i];
              return ListTile(
                title: Text(name),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LineAuditPage(isNew: false, lineName: name, isEdit: isEdit),
                    ),
                  ).then((_) => _loadSavedLines());
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Line Audit')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LineAuditPage(isNew: true))),
                child: const Text('New Line Audit'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: savedLineNames.isEmpty ? null : () => _showSavedLines(context, isEdit: false),
                child: const Text('Open Line Audit'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: savedLineNames.isEmpty ? null : () => _showSavedLines(context, isEdit: true),
                child: const Text('Edit Existing Line Audit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================
// ========= LINE AUDIT ===========
// ================================
class LineAuditPage extends StatefulWidget {
  final bool isNew;
  final String? lineName;
  final bool isEdit;
  const LineAuditPage({super.key, required this.isNew, this.lineName, this.isEdit = false});
  @override
  State<LineAuditPage> createState() => _LineAuditPageState();
}

class _LineAuditPageState extends State<LineAuditPage> {
  final _formKey = GlobalKey<FormState>();
  final ApiClient api = ApiClient();

  late String lineName;
  String melterType = 'ProBlue 4';
  int numHoses = 1;
  int numGuns = 1;

  List<Hose> hoses = [];
  List<Gun> guns = [];

  // UI Controllers (avoid resetting in build)
  List<TextEditingController> hoseCtrls = [];
  List<TextEditingController> gunCtrls = [];
  List<List<TextEditingController>> moduleCtrls = []; // per gun: module text
  List<List<TextEditingController>> nozzleCtrls = []; // per gun: nozzle text

  final melterTypes = const [
    'ProBlue 4', 'ProBlue 7', 'ProBlue 10', 'ProBlue 50',
    'AltaBlue', 'DuraBlue', 'MiniBlue', 'VersaBlue', 'Custom'
  ];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    lineName = widget.lineName ?? '';
    if (widget.isNew) {
      hoses = [Hose()];
      guns = [Gun()..modules = [Module()]];
    }
    _loadIfExisting();
  }

  Future<void> _loadIfExisting() async {
    setState(() => loading = true);
    try {
      if (!widget.isNew && widget.lineName != null) {
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = prefs.getString('line_audit_${widget.lineName}');
        if (jsonStr != null) {
          final data = json.decode(jsonStr);
          lineName = data['lineName'];
          melterType = data['melterType'];

          hoses = (data['hoses'] as List).map((h) => Hose(
            type: h['type'] ?? '',
            partNumber: h['partNumber'] ?? '',
          )).toList();

          guns = (data['guns'] as List).map((g) => Gun(
            type: g['type'] ?? '',
            partNumber: g['partNumber'] ?? '',
            modules: (g['modules'] as List).map((m) => Module(
              type: m['type'] ?? '',
              partNumber: m['partNumber'] ?? '',
              nozzle: m['nozzle'] ?? '',
              nozzlePartNumber: m['nozzlePartNumber'] ?? '',
            )).toList(),
          )).toList();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load error: $e')));
      }
    }

    // sync counts
    numHoses = hoses.isEmpty ? 1 : hoses.length;
    numGuns = guns.isEmpty ? 1 : guns.length;

    _ensureControllers();
    setState(() => loading = false);
  }

  void _ensureControllers() {
    // Hoses
    while (hoseCtrls.length < numHoses) hoseCtrls.add(TextEditingController());
    while (hoseCtrls.length > numHoses) hoseCtrls.removeLast();
    while (hoses.length < numHoses) hoses.add(Hose());
    while (hoses.length > numHoses) hoses.removeLast();
    for (int i = 0; i < hoses.length; i++) {
      hoseCtrls[i].text = displayProduct(hoses[i].type, hoses[i].partNumber);
    }

    // Guns
    while (gunCtrls.length < numGuns) gunCtrls.add(TextEditingController());
    while (gunCtrls.length > numGuns) gunCtrls.removeLast();
    while (guns.length < numGuns) guns.add(Gun()..modules = [Module()]);
    while (guns.length > numGuns) guns.removeLast();
    for (int i = 0; i < guns.length; i++) {
      gunCtrls[i].text = displayProduct(guns[i].type, guns[i].partNumber);
    }

    // Modules/Nozzles per gun
    while (moduleCtrls.length < guns.length) moduleCtrls.add([]);
    while (moduleCtrls.length > guns.length) moduleCtrls.removeLast();
    while (nozzleCtrls.length < guns.length) nozzleCtrls.add([]);
    while (nozzleCtrls.length > guns.length) nozzleCtrls.removeLast();

    for (int gi = 0; gi < guns.length; gi++) {
      final modules = guns[gi].modules;
      while (moduleCtrls[gi].length < modules.length) moduleCtrls[gi].add(TextEditingController());
      while (moduleCtrls[gi].length > modules.length) moduleCtrls[gi].removeLast();
      while (nozzleCtrls[gi].length < modules.length) nozzleCtrls[gi].add(TextEditingController());
      while (nozzleCtrls[gi].length > modules.length) nozzleCtrls[gi].removeLast();
      for (int mi = 0; mi < modules.length; mi++) {
        moduleCtrls[gi][mi].text = displayProduct(modules[mi].type, modules[mi].partNumber);
        nozzleCtrls[gi][mi].text = displayProduct(modules[mi].nozzle, modules[mi].nozzlePartNumber);
      }
    }
  }

  String displayProduct(String name, String sku) {
    if (name.isEmpty && sku.isEmpty) return '';
    if (name.isNotEmpty && sku.isNotEmpty) return '$name ($sku)';
    return name.isNotEmpty ? name : sku;
  }

  Future<void> _saveAudit() async {
    if (!_formKey.currentState!.validate()) return;
    final audit = {
      'lineName': lineName,
      'melterType': melterType,
      'hoses': hoses.map((h) => {
        'type': h.type == 'Custom' ? h.customType : h.type,
        'partNumber': h.partNumber,
      }).toList(),
      'guns': guns.map((g) => {
        'type': g.type == 'Custom' ? g.customType : g.type,
        'partNumber': g.partNumber,
        'modules': g.modules.map((m) => {
          'type': m.type == 'Custom' ? m.customType : m.type,
          'partNumber': m.partNumber,
          'nozzle': m.nozzle == 'Custom' ? m.customNozzle : m.nozzle,
          'nozzlePartNumber': m.nozzlePartNumber,
        }).toList(),
      }).toList(),
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('line_audit_$lineName', json.encode(audit));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $lineName')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
      }
    }
  }

  void _openInStoreBySKU(String sku) {
    if (sku.isEmpty) return;
    final encoded = Uri.encodeComponent(sku);
    final url = 'https://www.hotmeltsupplyco.com/search.php?search_query=$encoded';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // Suggestion helpers
  Future<List<String>> _suggestNames(String pattern) async {
    final prods = await api.searchProducts(pattern, limit: 10);
    final list = prods.map((p) => '${p.name} (${p.sku})').toList();
    // Always allow a Custom option
    if (!list.contains('Custom')) list.add('Custom');
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit: $lineName' : widget.isNew ? 'New Line Audit' : 'View: $lineName')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isNew || widget.isEdit)
                TextFormField(
                  initialValue: lineName,
                  decoration: const InputDecoration(labelText: 'Line Name *'),
                  onChanged: (v) => lineName = v,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                )
              else
                Text('Line: $lineName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              const SizedBox(height: 16),

              if (widget.isNew || widget.isEdit)
                DropdownButtonFormField<String>(
                  value: melterType,
                  items: melterTypes.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => melterType = v ?? melterType),
                  decoration: const InputDecoration(labelText: 'Melter Type'),
                )
              else
                Text('Melter: $melterType'),

              if ((widget.isNew || widget.isEdit) && melterType == 'Custom')
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Custom Melter'),
                  onChanged: (v) => melterType = 'Custom: $v',
                ),

              const SizedBox(height: 24),

              // Hoses
              if (widget.isNew || widget.isEdit)
                Row(
                  children: [
                    Text('Hoses ($numHoses)', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: numHoses,
                      items: List.generate(6, (i) => DropdownMenuItem<int>(value: i + 1, child: Text('${i + 1}'))),
                      onChanged: (v) => setState(() {
                        numHoses = v ?? 1;
                        _ensureControllers();
                      }),
                    ),
                  ],
                ),

              for (int i = 0; i < hoses.length; i++)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hose ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (widget.isNew || widget.isEdit)
                          TypeAheadField<String>(
                            suggestionsCallback: _suggestNames,
                            builder: (context, controller, focusNode) {
                              // Bind to persistent controller
                              return TextField(
                                controller: hoseCtrls[i]
                                  ..selection = TextSelection.fromPosition(TextPosition(offset: hoseCtrls[i].text.length)),
                                focusNode: focusNode,
                                decoration: const InputDecoration(labelText: 'Hose (Search by name/SKU)'),
                                onChanged: (v) {
                                  // allow manual SKU entry
                                  hoses[i].partNumber = extractSkuFromDisplay(v);
                                },
                              );
                            },
                            itemBuilder: (context, s) => ListTile(title: Text(s)),
                            onSelected: (selection) {
                              final name = selection.split(' (').first;
                              final sku = selection.contains(' (') ? selection.split(' (').last.replaceAll(')', '') : '';
                              setState(() {
                                hoses[i].type = name;
                                hoses[i].partNumber = sku;
                                hoseCtrls[i].text = selection;
                              });
                            },
                          )
                        else
                          ListTile(
                            title: Text(hoses[i].type.isEmpty ? '—' : hoses[i].type),
                            subtitle: Text('Part: ${hoses[i].partNumber.isEmpty ? '—' : hoses[i].partNumber}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () => _openInStoreBySKU(hoses[i].partNumber),
                            ),
                          ),
                        if ((widget.isNew || widget.isEdit) && hoses[i].type == 'Custom')
                          TextFormField(
                            decoration: const InputDecoration(labelText: 'Custom Hose Type'),
                            onChanged: (v) => hoses[i].customType = v,
                          ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // Guns
              if (widget.isNew || widget.isEdit)
                Row(
                  children: [
                    Text('Guns ($numGuns)', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: numGuns,
                      items: List.generate(6, (i) => DropdownMenuItem<int>(value: i + 1, child: Text('${i + 1}'))),
                      onChanged: (v) => setState(() {
                        numGuns = v ?? 1;
                        _ensureControllers();
                      }),
                    ),
                  ],
                ),

              for (int i = 0; i < guns.length; i++)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ExpansionTile(
                    title: Text('Gun ${i + 1}: ${guns[i].type.isEmpty ? 'Not selected' : guns[i].type}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.isNew || widget.isEdit)
                              TypeAheadField<String>(
                                suggestionsCallback: _suggestNames,
                                builder: (context, controller, focusNode) {
                                  return TextField(
                                    controller: gunCtrls[i]
                                      ..selection = TextSelection.fromPosition(TextPosition(offset: gunCtrls[i].text.length)),
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(labelText: 'Gun (Search by name/SKU)'),
                                    onChanged: (v) {
                                      guns[i].partNumber = extractSkuFromDisplay(v);
                                    },
                                  );
                                },
                                itemBuilder: (context, s) => ListTile(title: Text(s)),
                                onSelected: (selection) {
                                  final name = selection.split(' (').first;
                                  final sku = selection.contains(' (') ? selection.split(' (').last.replaceAll(')', '') : '';
                                  setState(() {
                                    guns[i].type = name;
                                    guns[i].partNumber = sku;
                                    gunCtrls[i].text = selection;
                                  });
                                },
                              )
                            else
                              ListTile(
                                title: Text(guns[i].type.isEmpty ? '—' : guns[i].type),
                                subtitle: Text('Part: ${guns[i].partNumber.isEmpty ? '—' : guns[i].partNumber}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.open_in_new),
                                  onPressed: () => _openInStoreBySKU(guns[i].partNumber),
                                ),
                              ),

                            if ((widget.isNew || widget.isEdit) && guns[i].type == 'Custom')
                              TextFormField(
                                decoration: const InputDecoration(labelText: 'Custom Gun Type'),
                                onChanged: (v) => guns[i].customType = v,
                              ),

                            const SizedBox(height: 16),

                            if (widget.isNew || widget.isEdit)
                              Row(
                                children: [
                                  Text('Modules: ${guns[i].modules.length}'),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      guns[i].modules.add(Module());
                                      _ensureControllers();
                                    }),
                                    icon: const Icon(Icons.add),
                                  ),
                                  if (guns[i].modules.length > 1)
                                    IconButton(
                                      onPressed: () => setState(() {
                                        guns[i].modules.removeLast();
                                        _ensureControllers();
                                      }),
                                      icon: const Icon(Icons.remove),
                                    ),
                                ],
                              ),

                            if (!widget.isNew && !widget.isEdit)
                              for (int j = 0; j < guns[i].modules.length; j++)
                                ListTile(
                                  title: Text('Module: ${guns[i].modules[j].type.isEmpty ? '—' : guns[i].modules[j].type}'),
                                  subtitle: Text('Nozzle: ${guns[i].modules[j].nozzle.isEmpty ? '—' : guns[i].modules[j].nozzle}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.open_in_new),
                                        onPressed: () => _openInStoreBySKU(guns[i].modules[j].partNumber),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.open_in_new),
                                        onPressed: () => _openInStoreBySKU(guns[i].modules[j].nozzlePartNumber),
                                      ),
                                    ],
                                  ),
                                )
                            else
                              for (int j = 0; j < guns[i].modules.length; j++)
                                Card(
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Module ${j + 1}'),
                                        TypeAheadField<String>(
                                          suggestionsCallback: _suggestNames,
                                          builder: (context, controller, focusNode) {
                                            return TextField(
                                              controller: moduleCtrls[i][j]
                                                ..selection = TextSelection.fromPosition(TextPosition(offset: moduleCtrls[i][j].text.length)),
                                              focusNode: focusNode,
                                              decoration: const InputDecoration(labelText: 'Module (Search by name/SKU)'),
                                            );
                                          },
                                          itemBuilder: (context, s) => ListTile(title: Text(s)),
                                          onSelected: (selection) {
                                            final name = selection.split(' (').first;
                                            final sku = selection.contains(' (') ? selection.split(' (').last.replaceAll(')', '') : '';
                                            setState(() {
                                              guns[i].modules[j].type = name;
                                              guns[i].modules[j].partNumber = sku;
                                              moduleCtrls[i][j].text = selection;
                                            });
                                          },
                                        ),
                                        if (guns[i].modules[j].type == 'Custom')
                                          TextFormField(
                                            decoration: const InputDecoration(labelText: 'Custom Module Type'),
                                            onChanged: (v) => guns[i].modules[j].customType = v,
                                          ),
                                        const SizedBox(height: 8),
                                        TypeAheadField<String>(
                                          suggestionsCallback: _suggestNames,
                                          builder: (context, controller, focusNode) {
                                            return TextField(
                                              controller: nozzleCtrls[i][j]
                                                ..selection = TextSelection.fromPosition(TextPosition(offset: nozzleCtrls[i][j].text.length)),
                                              focusNode: focusNode,
                                              decoration: const InputDecoration(labelText: 'Nozzle (Search by name/SKU)'),
                                            );
                                          },
                                          itemBuilder: (context, s) => ListTile(title: Text(s)),
                                          onSelected: (selection) {
                                            final name = selection.split(' (').first;
                                            final sku = selection.contains(' (') ? selection.split(' (').last.replaceAll(')', '') : '';
                                            setState(() {
                                              guns[i].modules[j].nozzle = name;
                                              guns[i].modules[j].nozzlePartNumber = sku;
                                              nozzleCtrls[i][j].text = selection;
                                            });
                                          },
                                        ),
                                        if (guns[i].modules[j].nozzle == 'Custom')
                                          TextFormField(
                                            decoration: const InputDecoration(labelText: 'Custom Nozzle Type'),
                                            onChanged: (v) => guns[i].modules[j].customNozzle = v,
                                          ),
                                        if (guns[i].modules.length > 1)
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: IconButton(
                                              onPressed: () => setState(() {
                                                guns[i].modules.removeAt(j);
                                                _ensureControllers();
                                              }),
                                              icon: const Icon(Icons.delete),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              Center(
                child: ElevatedButton(
                  onPressed: widget.isNew || widget.isEdit ? _saveAudit : () => Navigator.pop(context),
                  child: Text(widget.isNew || widget.isEdit ? 'Save Line Audit' : 'Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================
// =========== MODELS =============
// ================================
class Hose {
  String type;
  String customType;
  String partNumber;
  Hose({this.type = '', this.customType = '', this.partNumber = ''});
}

class Module {
  String type;
  String customType;
  String partNumber;
  String nozzle;
  String customNozzle;
  String nozzlePartNumber;
  Module({
    this.type = '',
    this.customType = '',
    this.partNumber = '',
    this.nozzle = '',
    this.customNozzle = '',
    this.nozzlePartNumber = '',
  });
}

class Gun {
  String type;
  String customType;
  String partNumber;
  List<Module> modules;
  Gun({
    this.type = '',
    this.customType = '',
    this.partNumber = '',
    List<Module>? modules,
  }) : modules = modules ?? [Module()];
}

class ProductSuggestion {
  final int id;
  final String name;
  final String sku;
  final String url;
  ProductSuggestion({required this.id, required this.name, required this.sku, required this.url});
  factory ProductSuggestion.fromJson(Map<String, dynamic> json) {
    return ProductSuggestion(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      url: 'https://www.hotmeltsupplyco.com${((json['custom_url'] ?? {})['url'] ?? '')}',
    );
  }
}

// ================================
// ========== UTILITIES ===========
// ================================
String extractSkuFromDisplay(String display) {
  // from "Name (SKU)" -> SKU
  final start = display.lastIndexOf('(');
  final end = display.endsWith(')');
  if (start != -1 && end) {
    return display.substring(start + 1, display.length - 1).trim();
  }
  return display.trim();
}
