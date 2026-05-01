import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Firebase Imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// CSV & File System Imports
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const GymApp());
}

class GymApp extends StatelessWidget {
  const GymApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF00D1B2),
      ),
      home: const AuthGate(),
    );
  }
}

// --- GATEKEEPER WIDGET ---
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return const MainNavigation();
        }
        return const LoginPage();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  int _currentDayIndex = 0;
  bool _isLoading = true;
  List<dynamic> _programData = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          _programData = doc.data()!['program'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error loading from Firebase: $e");
    }
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'program': _programData,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {});
    } catch (e) {
      debugPrint("Error saving to Firebase: $e");
    }
  }

  int get totalPlannedDays {
    int total = 0;
    for (var month in _programData) {
      for (var week in month['weeks']) {
        total += (week['days'] as List).length;
      }
    }
    return total;
  }

  Map<String, dynamic>? get _activeSession {
    try {
      return _programData[0]['weeks'][0]['days'][_currentDayIndex];
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00D1B2)),
        ),
      );
    }

    final List<Widget> tabs = [
      DashboardPage(
        program: _programData,
        currentDayIdx: _currentDayIndex,
        totalDays: totalPlannedDays,
        onStart: () => setState(() => _currentIndex = 1),
        onNextSession: (nextIdx) {
          setState(() {
            int totalInWeek = _programData[0]['weeks'][0]['days'].length;
            _currentDayIndex = nextIdx < totalInWeek ? nextIdx : 0;
          });
        },
      ),
      WorkoutSessionPage(
        dayData: _activeSession,
        program: _programData,
        onSave: _save,
      ),
      ProgramBuilderPage(program: _programData, onUpdate: _save),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00D1B2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.dumbbell,
                color: Colors.black,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "GymTracker",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.logOut, size: 18),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF0A0A0A),
        selectedItemColor: const Color(0xFF00D1B2),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.playCircle),
            label: "Workout",
          ),
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.layers),
            label: "Build",
          ),
        ],
      ),
    );
  }
}

// --- LOGIN PAGE ---
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();

  Future<void> _auth() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _email.text.trim(),
            password: _pass.text.trim(),
          );
        } catch (signUpError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(signUpError.toString())));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Authentication Error")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              LucideIcons.dumbbell,
              size: 64,
              color: Color(0xFF00D1B2),
            ),
            const SizedBox(height: 20),
            const Text(
              "GYM TRACKER",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: _pass,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _auth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D1B2),
                ),
                child: const Text(
                  "LOGIN / SIGN UP",
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- DASHBOARD PAGE ---
class DashboardPage extends StatelessWidget {
  final List<dynamic> program;
  final int currentDayIdx;
  final int totalDays;
  final VoidCallback onStart;
  final Function(int) onNextSession;

  const DashboardPage({
    super.key,
    required this.program,
    required this.onStart,
    required this.currentDayIdx,
    required this.totalDays,
    required this.onNextSession,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? activeDay;
    try {
      activeDay = program[0]['weeks'][0]['days'][currentDayIdx];
    } catch (_) {}
    final exercises = activeDay != null ? (activeDay['exercises'] as List) : [];

    bool isDayComplete =
        exercises.isNotEmpty &&
        exercises.every((ex) {
          List sets = ex['sets'];
          return sets.isNotEmpty && sets.every((s) => s['done'] == true);
        });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statBox(
                  "Days",
                  "${currentDayIdx + 1}/$totalDays",
                  LucideIcons.calendar,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBox(
                  "Exercises",
                  "${exercises.length}",
                  LucideIcons.trendingUp,
                  Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBox(
                  "Next up",
                  activeDay != null ? activeDay['name'] : "--",
                  LucideIcons.zap,
                  Colors.purpleAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1F1D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF00D1B2).withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "TODAY'S WORKOUT",
                          style: TextStyle(
                            color: Color(0xFF00D1B2),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          activeDay != null ? activeDay['name'] : "No Workout",
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${exercises.length} Exercises",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                    isDayComplete
                        ? GestureDetector(
                            onTap: () => onNextSession(currentDayIdx + 1),
                            child: _actionButton(
                              "Next Session",
                              LucideIcons.arrowRight,
                            ),
                          )
                        : GestureDetector(
                            onTap: onStart,
                            child: _actionButton("Start", LucideIcons.play),
                          ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildExerciseGrid(exercises),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String t, String v, IconData i, Color c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF161618),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(i, color: c, size: 18),
        const SizedBox(height: 8),
        Text(t, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(
          v,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Widget _actionButton(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF00BCD4), Color(0xFF00D1B2)],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.black, size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _buildExerciseGrid(List exercises) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    itemCount: exercises.length > 4 ? 4 : exercises.length,
    itemBuilder: (ctx, i) => Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.dumbbell, size: 12, color: Color(0xFF00D1B2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              exercises[i]['name'],
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

// --- WORKOUT SESSION PAGE ---
class WorkoutSessionPage extends StatefulWidget {
  final Map<String, dynamic>? dayData;
  final List<dynamic> program;
  final VoidCallback onSave;
  const WorkoutSessionPage({
    super.key,
    this.dayData,
    required this.program,
    required this.onSave,
  });
  @override
  State<WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _WorkoutSessionPageState extends State<WorkoutSessionPage> {
  final Map<String, bool> _showNotes = {};

  double get progress {
    if (widget.dayData == null) return 0.0;
    List exercises = widget.dayData!['exercises'];
    if (exercises.isEmpty) return 0.0;
    int completed = exercises
        .where(
          (ex) =>
              (ex['sets'] as List).isNotEmpty &&
              (ex['sets'] as List).every((s) => s['done'] == true),
        )
        .length;
    return completed / exercises.length;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dayData == null)
      return const Center(
        child: Text("Build your first day to start training!"),
      );
    List exercises = widget.dayData!['exercises'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.dayData!['name'],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "${(progress * 100).toInt()}%",
                    style: const TextStyle(
                      color: Color(0xFF00D1B2),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white10,
                  color: const Color(0xFF00D1B2),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              ...List.generate(
                exercises.length,
                (i) => _exerciseCard(exercises[i], i),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _showPlanView(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00D1B2)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.list, color: Color(0xFF00D1B2)),
                label: const Text(
                  "View All Plan",
                  style: TextStyle(
                    color: Color(0xFF00D1B2),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _exerciseCard(dynamic ex, int i) {
    bool finished =
        (ex['sets'] as List).isNotEmpty &&
        (ex['sets'] as List).every((s) => s['done'] == true);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: finished ? const Color(0xFF0D1F1D) : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: finished
              ? const Color(0xFF00D1B2).withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                ex['name'],
                style: TextStyle(
                  color: finished ? const Color(0xFF00D1B2) : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (finished)
                const Icon(
                  LucideIcons.checkCircle2,
                  color: Color(0xFF00D1B2),
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(
            (ex['sets'] as List).length,
            (sIdx) => _setRow(ex['sets'][sIdx], sIdx, ex, "${i}_$sIdx"),
          ),
        ],
      ),
    );
  }

  Widget _setRow(dynamic set, int sIdx, dynamic ex, String noteKey) {
    bool isTime = ex['unit'] == 'run (mins)';
    bool isDist = ex['unit'] == 'run (km)';
    String label = isTime ? 'mins' : (isDist ? 'km' : 'reps');

    return Column(
      children: [
        Row(
          children: [
            InkWell(
              onTap: () {
                setState(() => set['done'] = !(set['done'] ?? false));
                widget.onSave();
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: set['done'] == true
                      ? const Color(0xFF00D1B2)
                      : Colors.white10,
                ),
                child: set['done'] == true
                    ? const Icon(
                        LucideIcons.check,
                        size: 14,
                        color: Colors.black,
                      )
                    : Center(
                        child: Text(
                          "${sIdx + 1}",
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 15),
            Text("${set['reps']} $label"),
            if (!isTime && !isDist) ...[
              const SizedBox(width: 8),
              const Text("×", style: TextStyle(color: Colors.grey)),
              const SizedBox(width: 8),
              Text(
                "${set['weight']} ${ex['unit']}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            const Spacer(),
            IconButton(
              icon: Icon(
                LucideIcons.stickyNote,
                size: 16,
                color: (set['notes']?.isNotEmpty ?? false)
                    ? const Color(0xFF00D1B2)
                    : Colors.grey,
              ),
              onPressed: () => setState(
                () => _showNotes[noteKey] = !(_showNotes[noteKey] ?? false),
              ),
            ),
          ],
        ),
        if (_showNotes[noteKey] == true)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 10),
            child: TextField(
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: "Add note...",
                border: InputBorder.none,
                isDense: true,
              ),
              controller: TextEditingController(text: set['notes'] ?? "")
                ..selection = TextSelection.collapsed(
                  offset: (set['notes'] ?? "").length,
                ),
              onSubmitted: (val) {
                set['notes'] = val;
                widget.onSave();
                setState(() => _showNotes[noteKey] = false);
              },
            ),
          ),
      ],
    );
  }

  void _showPlanView(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ReadOnlyProgramView(
          program: widget.program,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

// --- PROGRAM BUILDER PAGE ---
class ProgramBuilderPage extends StatelessWidget {
  final List<dynamic> program;
  final VoidCallback onUpdate;
  const ProgramBuilderPage({
    super.key,
    required this.program,
    required this.onUpdate,
  });

  // --- CSV FEATURE: EXPORT TEMPLATE ---
  Future<void> _generateTemplate() async {
    // 1. Create your CSV content
    List<List<String>> csvContent = [
      ["Month", "Week", "Day", "Exercise", "Unit", "Reps_List", "Weights_List"],
      [
        "Phase 1",
        "Week 1",
        "Day 1 (Pull)",
        "Lat Pull Down",
        "kg",
        "15-14-13",
        "40-45-50",
      ],
    ];

    // 2. Convert to String
    String csvString = const ListToCsvConverter().convert(csvContent);

    // 3. Convert String to Bytes (Required for universal saving)
    Uint8List bytes = Uint8List.fromList(csvString.codeUnits);

    // 4. Save the file using FileSaver (Works on Android, iOS, Web, Windows, Mac)
    await FileSaver.instance.saveFile(
      name: 'workout_template',
      bytes: bytes,
      ext: 'csv',
      mimeType: MimeType.csv,
    );
  }

  // --- CSV FEATURE: IMPORT LOGIC ---
  Future<void> _importCSV(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null) return;

    try {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final csvString = utf8.decode(bytes);
      final rows = const CsvToListConverter().convert(csvString);

      if (rows.length < 2) return;
      rows.removeAt(0); // Remove Header

      for (var row in rows) {
        if (row.length < 7) continue;
        String mName = row[0].toString();
        String wName = row[1].toString();
        String dName = row[2].toString();
        String eName = row[3].toString();
        String unit = row[4].toString();
        String repsListRaw = row[5].toString();
        String weightsListRaw = row[6].toString();

        var month = program.firstWhere(
          (m) => m['name'] == mName,
          orElse: () {
            var m = {"name": mName, "weeks": []};
            program.add(m);
            return m;
          },
        );

        var week = month['weeks'].firstWhere(
          (w) => w['name'] == wName,
          orElse: () {
            var w = {"name": wName, "days": []};
            month['weeks'].add(w);
            return w;
          },
        );

        var day = week['days'].firstWhere(
          (d) => d['name'] == dName,
          orElse: () {
            var d = {"name": dName, "exercises": []};
            week['days'].add(d);
            return d;
          },
        );

        List<String> reps = repsListRaw.split('-');
        List<String> weights = weightsListRaw.split('-');
        List<Map<String, dynamic>> sets = [];

        for (int i = 0; i < reps.length; i++) {
          sets.add({
            "reps": double.tryParse(reps[i].trim()) ?? 0,
            "weight": double.tryParse(weights[i].trim()) ?? 0,
            "done": false,
          });
        }
        day['exercises'].add({"name": eName, "unit": unit, "sets": sets});
      }

      onUpdate();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Imported!")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Program Builder",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // ADDED CSV ACTIONS HERE
          IconButton(
            icon: const Icon(LucideIcons.download),
            onPressed: _generateTemplate,
          ),
          IconButton(
            icon: const Icon(LucideIcons.fileUp),
            onPressed: () => _importCSV(context),
          ),
          IconButton(
            icon: const Icon(LucideIcons.plusCircle, color: Color(0xFF00D1B2)),
            onPressed: () => _addMonth(),
          ),
        ],
      ),
      body: program.isEmpty
          ? const Center(child: Text("Tap + to add your first month"))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: program.length,
              itemBuilder: (context, mIdx) => _buildMonthSection(context, mIdx),
            ),
    );
  }

  Widget _buildMonthSection(BuildContext context, int mIdx) {
    var month = program[mIdx];
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(
        month['name'].toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF00D1B2),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(LucideIcons.edit2, size: 16),
            onPressed: () => _rename(context, month),
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 16),
            onPressed: () => _duplicateMonth(mIdx),
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
            onPressed: () => _deleteMonth(mIdx),
          ),
        ],
      ),
      children: [
        ...(month['weeks'] as List)
            .asMap()
            .entries
            .map((e) => _buildWeekSection(context, mIdx, e.key))
            .toList(),
        ListTile(
          leading: const Icon(LucideIcons.plus, size: 18),
          title: const Text("Add New Week"),
          onTap: () => _addWeek(mIdx),
        ),
      ],
    );
  }

  Widget _buildWeekSection(BuildContext context, int mIdx, int wIdx) {
    var week = program[mIdx]['weeks'][wIdx];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                week['name'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(LucideIcons.edit2, size: 14),
                onPressed: () => _rename(context, week),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 14),
                onPressed: () => _duplicateWeek(mIdx, wIdx),
              ),
              IconButton(
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 14,
                  color: Colors.grey,
                ),
                onPressed: () => _deleteWeek(mIdx, wIdx),
              ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: (week['days'] as List).length + 1,
            itemBuilder: (ctx, dIdx) {
              if (dIdx == week['days'].length)
                return _addBtn(() => _addDay(mIdx, wIdx));
              return _dayCard(context, mIdx, wIdx, dIdx, week['days'][dIdx]);
            },
          ),
        ],
      ),
    );
  }

  Widget _dayCard(
    BuildContext context,
    int mIdx,
    int wIdx,
    int dIdx,
    dynamic day,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => ExerciseEditor(dayData: day, onSave: onUpdate),
              ),
            ),
            onLongPress: () => _rename(context, day),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    "${day['exercises'].length} exercises",
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Row(
              children: [
                _smallIcon(
                  LucideIcons.copy,
                  () => _duplicateDay(mIdx, wIdx, dIdx),
                ),
                _smallIcon(
                  LucideIcons.trash2,
                  () => _deleteDay(mIdx, wIdx, dIdx),
                  color: Colors.red.withOpacity(0.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallIcon(IconData i, VoidCallback fn, {Color? color}) =>
      GestureDetector(
        onTap: fn,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(i, size: 12, color: color ?? Colors.grey),
        ),
      );
  Widget _addBtn(VoidCallback fn) => GestureDetector(
    onTap: fn,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(LucideIcons.plus, color: Colors.grey),
    ),
  );

  void _addMonth() {
    program.add({"name": "New Month", "weeks": []});
    onUpdate();
  }

  void _deleteMonth(int i) {
    program.removeAt(i);
    onUpdate();
  }

  void _duplicateMonth(int i) {
    program.add(json.decode(json.encode(program[i])));
    onUpdate();
  }

  void _addWeek(int m) {
    program[m]['weeks'].add({"name": "New Week", "days": []});
    onUpdate();
  }

  void _deleteWeek(int m, int w) {
    program[m]['weeks'].removeAt(w);
    onUpdate();
  }

  void _duplicateWeek(int m, int w) {
    program[m]['weeks'].add(json.decode(json.encode(program[m]['weeks'][w])));
    onUpdate();
  }

  void _addDay(int m, int w) {
    program[m]['weeks'][w]['days'].add({"name": "New Day", "exercises": []});
    onUpdate();
  }

  void _deleteDay(int m, int w, int d) {
    program[m]['weeks'][w]['days'].removeAt(d);
    onUpdate();
  }

  void _duplicateDay(int m, int w, int d) {
    program[m]['weeks'][w]['days'].add(
      json.decode(json.encode(program[m]['weeks'][w]['days'][d])),
    );
    onUpdate();
  }

  void _rename(BuildContext context, dynamic item) {
    TextEditingController c = TextEditingController(text: item['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename"),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () {
              item['name'] = c.text;
              onUpdate();
              Navigator.pop(ctx);
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }
}

// --- EXERCISE EDITOR PAGE ---
class ExerciseEditor extends StatefulWidget {
  final Map<String, dynamic> dayData;
  final VoidCallback onSave;
  const ExerciseEditor({
    super.key,
    required this.dayData,
    required this.onSave,
  });
  @override
  State<ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<ExerciseEditor> {
  final List<String> validUnits = [
    'kg',
    'plate',
    'lbs',
    'run (mins)',
    'run (km)',
  ];
  @override
  Widget build(BuildContext context) {
    List exList = widget.dayData['exercises'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.dayData['name']),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: exList.length,
        itemBuilder: (context, i) => _exTile(i),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00D1B2),
        onPressed: () {
          setState(
            () =>
                exList.add({"name": "New Exercise", "unit": "kg", "sets": []}),
          );
          widget.onSave();
        },
        child: const Icon(LucideIcons.plus, color: Colors.black),
      ),
    );
  }

  Widget _exTile(int i) {
    var ex = widget.dayData['exercises'][i];
    if (!validUnits.contains(ex['unit'])) ex['unit'] = 'run (mins)';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _renameEx(ex),
                  child: Text(
                    ex['name'],
                    style: const TextStyle(
                      color: Color(0xFF00D1B2),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: ex['unit'],
                underline: const SizedBox(),
                items: validUnits
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(u, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() => ex['unit'] = v);
                  widget.onSave();
                },
              ),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 14),
                onPressed: () {
                  setState(
                    () => widget.dayData['exercises'].add(
                      json.decode(json.encode(ex)),
                    ),
                  );
                  widget.onSave();
                },
              ),
              IconButton(
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 14,
                  color: Colors.redAccent,
                ),
                onPressed: () {
                  setState(() => widget.dayData['exercises'].removeAt(i));
                  widget.onSave();
                },
              ),
            ],
          ),
          ...List.generate(ex['sets'].length, (si) => _setRow(ex, si)),
          TextButton(
            onPressed: () {
              setState(
                () =>
                    ex['sets'].add({"reps": 10, "weight": 0.0, "done": false}),
              );
              widget.onSave();
            },
            child: const Text("+ Add Set"),
          ),
        ],
      ),
    );
  }

  Widget _setRow(dynamic ex, int si) {
    var s = ex['sets'][si];
    bool isCardio = ex['unit'] == 'run (mins)' || ex['unit'] == 'run (km)';
    String label = ex['unit'] == 'run (mins)'
        ? 'mins'
        : (ex['unit'] == 'run (km)' ? 'km' : 'reps');
    return Row(
      children: [
        Checkbox(
          value: s['done'],
          activeColor: const Color(0xFF00D1B2),
          onChanged: (v) {
            setState(() => s['done'] = v);
            widget.onSave();
          },
        ),
        Text("Set ${si + 1}"),
        const Spacer(),
        _num(s, 'reps', label),
        if (!isCardio) ...[
          const SizedBox(width: 5),
          _num(s, 'weight', ex['unit']),
        ],
      ],
    );
  }

  Widget _num(dynamic s, String k, String u) => GestureDetector(
    onTap: () {
      TextEditingController c = TextEditingController(text: s[k].toString());
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => s[k] = double.tryParse(c.text) ?? 0);
                widget.onSave();
                Navigator.pop(ctx);
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
    },
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text("${s[k]} $u", style: const TextStyle(fontSize: 12)),
    ),
  );

  void _renameEx(dynamic ex) {
    TextEditingController c = TextEditingController(text: ex['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename Exercise"),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => ex['name'] = c.text);
              widget.onSave();
              Navigator.pop(ctx);
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }
}

// --- READ ONLY PROGRAM VIEW ---
class ReadOnlyProgramView extends StatelessWidget {
  final List<dynamic> program;
  final ScrollController scrollController;
  const ReadOnlyProgramView({
    super.key,
    required this.program,
    required this.scrollController,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Text(
                "Full Training Plan",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: program.length,
            itemBuilder: (context, mIdx) {
              var month = program[mIdx];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    month['name'].toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF00D1B2),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 30),
                  ...(month['weeks'] as List)
                      .map((week) => _buildWeek(context, week))
                      .toList(),
                  const SizedBox(height: 30),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeek(BuildContext context, dynamic week) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          week['name'],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: (week['days'] as List).length,
          itemBuilder: (ctx, dIdx) {
            var day = week['days'][dIdx];
            return InkWell(
              onTap: () => _showDayDetail(context, day),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161618),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      day['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "${day['exercises'].length} exercises",
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _showDayDetail(BuildContext context, dynamic day) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  day['name'],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00D1B2),
                  ),
                ),
                const Icon(LucideIcons.eye, color: Colors.grey, size: 20),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: (day['exercises'] as List).length,
                separatorBuilder: (c, i) =>
                    const Divider(color: Colors.white10),
                itemBuilder: (c, i) {
                  var ex = day['exercises'][i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${(ex['sets'] as List).length} sets • ${ex['unit']}",
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Close Preview"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
