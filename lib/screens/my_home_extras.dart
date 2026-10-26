part of 'communication_screen.dart';

// =====================================================================
// Round 7 additions to My Home:
//   online / last seen, chat settings, emoji picker, voice + video notes,
//   polls, location, contacts, privacy settings (Telegram style)
// =====================================================================

/// Who is connected right now (from the "online-users" presence channel).
final ValueNotifier<Set<String>> _onlineNow = ValueNotifier(<String>{});

/// The signed-in user's chat settings (stored in user_privacy.chat_prefs).
class _ChatPrefs {
  static double textSize = 14;
  static bool enterToSend = true;
  static String wallpaper = 'default';
  static bool typing = true;
  static String lastSeenRule = 'everyone';
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static void apply(Map<String, dynamic> row) {
    final p = row['chat_prefs'] is Map ? Map<String, dynamic>.from(row['chat_prefs'] as Map) : const <String, dynamic>{};
    textSize = ((p['text_size'] as num?)?.toDouble() ?? 14).clamp(12, 22).toDouble();
    enterToSend = p['enter_to_send'] != false;
    wallpaper = (p['wallpaper'] ?? 'default').toString();
    typing = row['typing'] != false;
    lastSeenRule = (row['last_seen'] ?? 'everyone').toString();
    changed.value++;
  }

  static Map<String, dynamic> toPrefs() => {'text_size': textSize, 'enter_to_send': enterToSend, 'wallpaper': wallpaper};

  // darkify:off — chat backgrounds are chosen colours
  static const Map<String, (String, List<Color>)> wallpapers = {
    'default': ('Default', [Color(0xFFE7EBF0), Color(0xFFE7EBF0)]),
    'lavender': ('Lavender', [Color(0xFFEDE7F6), Color(0xFFF3E5F5)]),
    'sky': ('Sky', [Color(0xFFE0F2FE), Color(0xFFDBEAFE)]),
    'mint': ('Mint', [Color(0xFFDCFCE7), Color(0xFFECFDF5)]),
    'peach': ('Peach', [Color(0xFFFFEDD5), Color(0xFFFFF7ED)]),
    'rose': ('Rose', [Color(0xFFFCE7F3), Color(0xFFFFF1F2)]),
    'night': ('Night', [Color(0xFF1E293B), Color(0xFF0F172A)]),
  };
  // darkify:on

  static BoxDecoration get background {
    final w = wallpapers[wallpaper] ?? wallpapers['default']!;
    return BoxDecoration(gradient: LinearGradient(colors: [AppPalette.solid(w.$2.first), AppPalette.solid(w.$2.last)], begin: Alignment.topLeft, end: Alignment.bottomRight));
  }
}

/// "online", "last seen 5 minutes ago", "last seen recently" …
String _lastSeenText({required bool online, required bool visible, DateTime? lastSeen}) {
  if (!visible) return 'last seen recently';
  if (online) return 'online';
  if (lastSeen == null) return 'last seen a long time ago';
  final d = DateTime.now().difference(lastSeen);
  if (d.inMinutes < 1) return 'last seen just now';
  if (d.inMinutes < 60) return 'last seen ${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
  if (day == today) return 'last seen today at ${DateFormat('HH:mm').format(lastSeen)}';
  if (today.difference(day).inDays == 1) return 'last seen yesterday at ${DateFormat('HH:mm').format(lastSeen)}';
  if (today.difference(day).inDays < 7) return 'last seen ${DateFormat('EEEE').format(lastSeen)}';
  return 'last seen ${DateFormat('d MMM yyyy').format(lastSeen)}';
}

bool _isOnline(String? userId, bool visible) => userId != null && visible && _onlineNow.value.contains(userId);

/// Avatar with a green "online" dot.
class _PresenceAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final bool group;
  final String? userId;
  final bool visible;
  const _PresenceAvatar({required this.name, this.url, this.size = 44, this.group = false, this.userId, this.visible = false});

  @override
  Widget build(BuildContext context) {
    final avatar = _Avatar(name: name, url: url, size: size, group: group);
    if (userId == null) return avatar;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _onlineNow,
      builder: (context, online, _) {
        final on = visible && online.contains(userId);
        if (!on) return avatar;
        return Stack(clipBehavior: Clip.none, children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle, border: Border.all(color: AppPalette.bg(Colors.white)!, width: 2)),
            ),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------
// Emoji picker (categories + recently used)
// ---------------------------------------------------------------------
const Map<String, (IconData, String)> _emojiSets = {
  'Smileys': (
    Icons.emoji_emotions_outlined,
    '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 😮‍💨 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 🤯 🤠 🥳 🥸 😎 🤓 🧐 😕 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 💩 🤡 👻 👽 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾'
  ),
  'People': (
    Icons.waving_hand_outlined,
    '👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦵 🦶 👂 👃 🧠 👀 👁️ 👅 👄 👶 🧒 👦 👧 🧑 👱 👨 🧔 👩 🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 🧏 🙇 🤦 🤷 👮 💂 👷 🤴 👸 👳 👲 🧕 🤵 👰 🤰 🤱 👼 🎅 🦸 🧙 🧚 💆 💇 🚶 🧍 🧎 🏃 💃 🕺 👯 🧖 🧗 🤸 ⛹️ 🏋️ 🚴 🤼 🤽 🤾 🤹 🧘 🛀 👭 👫 👬 💏 💑 👪 🗣️ 👤 👥'
  ),
  'Hearts': (
    Icons.favorite_border,
    '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ♥️ 😍 🥰 😘 💋 💌 💐 🌹 🌷 🌸 💒 💍 🫶 🤗'
  ),
  'Nature': (
    Icons.eco_outlined,
    '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🐢 🐍 🦎 🐙 🦑 🦀 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🐅 🐆 🦓 🦍 🐘 🦛 🦏 🐪 🐫 🦒 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🐐 🦌 🐕 🐈 🐓 🦃 🕊️ 🐇 🌵 🎄 🌲 🌳 🌴 🌱 🌿 ☘️ 🍀 🍃 🍂 🍁 🍄 🌾 💐 🌷 🌹 🥀 🌺 🌸 🌼 🌻 🌞 🌝 🌛 🌜 🌚 🌕 🌙 🌎 🌍 🌏 🪐 ⭐ 🌟 ✨ ⚡ ☄️ 💥 🔥 🌪️ 🌈 ☀️ 🌤️ ⛅ 🌥️ ☁️ 🌦️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ ☃️ ⛄ 🌬️ 💨 💧 💦 ☔ ☂️ 🌊'
  ),
  'Food': (
    Icons.restaurant_outlined,
    '🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🌽 🥕 🧄 🧅 🥔 🍠 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🥙 🧆 🌮 🌯 🥗 🥘 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🥠 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 ☕ 🍵 🧃 🥤 🧋 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🧊 🥄 🍴 🍽️'
  ),
  'Activity': (
    Icons.sports_soccer_outlined,
    '⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🏓 🏸 🏒 🏑 🥍 🏏 🥅 ⛳ 🏹 🎣 🥊 🥋 🎽 🛹 ⛸️ 🥌 🎿 ⛷️ 🏂 🏆 🥇 🥈 🥉 🏅 🎖️ 🏵️ 🎗️ 🎫 🎟️ 🎪 🤹 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🪕 🎻 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩 🎉 🎊 🎈 🎁 🎀 🪅'
  ),
  'Travel': (
    Icons.directions_car_outlined,
    '🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🚚 🚛 🚜 🛵 🏍️ 🚲 🛴 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ ⛽ 🚧 🚦 🚥 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲ ⛱️ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺ 🏠 🏡 🏘️ 🏚️ 🏗️ 🏭 🏢 🏬 🏣 🏤 🏥 🏦 🏨 🏪 🏫 🏩 💒 🏛️ ⛪ 🕌 🕍 🛕 🕋 ⛩️'
  ),
  'Objects': (
    Icons.lightbulb_outline,
    '⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 🎞️ 📞 ☎️ 📟 📠 📺 📻 🎙️ 🎚️ 🎛️ 🧭 ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ 📡 🔋 🔌 💡 🔦 🕯️ 🧯 💸 💵 💴 💶 💷 💰 💳 💎 ⚖️ 🧰 🔧 🔨 ⚒️ 🛠️ ⛏️ 🔩 ⚙️ 🧱 ⛓️ 🧲 🔫 💣 🧨 🪓 🔪 🗡️ ⚔️ 🛡️ 🚬 ⚰️ ⚱️ 🏺 🔮 📿 🧿 💈 ⚗️ 🔭 🔬 🕳️ 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🧺 🧻 🚽 🚰 🚿 🛁 🧼 🧽 🪒 🧴 🛎️ 🔑 🗝️ 🚪 🪑 🛋️ 🛏️ 🧸 🖼️ 🛍️ 🛒 🎁 🎈 🎏 🎀 🎊 🎉 🎎 🏮 🎐 🧧 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 📪 📫 📬 📭 📮 📯 📜 📃 📄 📑 🧾 📊 📈 📉 🗒️ 🗓️ 📆 📅 🗑️ 📇 🗃️ 🗳️ 🗄️ 📋 📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 🔗 📎 🖇️ 📐 📏 🧮 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓'
  ),
  'Symbols': (
    Icons.tag,
    '✝️ ☦️ ✡️ 🕎 ☮️ ☯️ 🕉️ ☪️ 🛐 ⛎ ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓ 🆔 ⚛️ ☢️ ☣️ 📴 📳 🈶 🈚 🆚 💮 🉐 ㊙️ ㊗️ 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕ 🛑 ⛔ 📛 🚫 💯 💢 ♨️ 🚷 🚯 🚳 🚱 🔞 📵 🚭 ❗ ❕ ❓ ❔ ‼️ ⁉️ 🔅 🔆 〽️ ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 🈯 💹 ❇️ ✳️ ❎ 🌐 💠 Ⓜ️ 🌀 💤 🏧 🚾 ♿ 🅿️ 🚹 🚺 🚼 🚻 🚮 🎦 📶 🈁 🔣 ℹ️ 🔤 🔡 🔠 🆖 🆗 🆙 🆒 🆕 🆓 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔢 #️⃣ *️⃣ ▶️ ⏸️ ⏯️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ ⏫ ⏬ ◀️ 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ ⤴️ ⤵️ 🔀 🔁 🔂 🔄 🔃 🎵 🎶 ➕ ➖ ➗ ✖️ ♾️ 💲 💱 ™️ ©️ ®️ 〰️ ➰ ➿ 🔚 🔙 🔛 🔝 🔜 ✔️ ☑️ 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 ▪️ ▫️ ◾ ◽ ◼️ ◻️ 🟥 🟧 🟨 🟩 🟦 🟪 ⬛ ⬜ 🟫 🔈 🔇 🔉 🔊 🔔 🔕 📣 📢 💬 💭 🗯️ ♠️ ♣️ ♥️ ♦️ 🃏 🎴 🀄'
  ),
  'Flags': (
    Icons.flag_outlined,
    '🏁 🚩 🎌 🏴 🏳️ 🏳️‍🌈 🇺🇬 🇰🇪 🇹🇿 🇷🇼 🇧🇮 🇸🇸 🇨🇩 🇪🇹 🇳🇬 🇬🇭 🇿🇦 🇿🇲 🇲🇼 🇲🇿 🇿🇼 🇰🇷 🇯🇵 🇨🇳 🇮🇳 🇺🇸 🇬🇧 🇨🇦 🇦🇺 🇩🇪 🇫🇷 🇮🇹 🇪🇸 🇧🇷 🇮🇱 🇸🇦 🇦🇪 🇪🇬'
  ),
};

Future<String?> _showEmojiPicker(BuildContext context) async {
  List<String> recent = [];
  try {
    final prefs = await SharedPreferences.getInstance();
    recent = prefs.getStringList('chat_recent_emojis') ?? [];
  } catch (_) {}
  if (!context.mounted) return null;
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final cats = [if (recent.isNotEmpty) 'Recent', ..._emojiSets.keys];
      final w = MediaQuery.of(ctx).size.width;
      final cols = w < 420 ? 8 : w < 700 ? 10 : 14;
      return SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.5,
        child: DefaultTabController(
          length: cats.length,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final c in cats)
                  Tab(
                    height: 38,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(c == 'Recent' ? Icons.history_rounded : _emojiSets[c]!.$1, size: 18),
                      const SizedBox(width: 4),
                      Text(c, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                for (final c in cats)
                  GridView.count(
                    padding: const EdgeInsets.all(8),
                    crossAxisCount: cols,
                    children: [
                      for (final e in (c == 'Recent' ? recent : _emojiSets[c]!.$2.split(' ').where((x) => x.isNotEmpty)))
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.pop(ctx, e),
                          child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
                        ),
                    ],
                  ),
              ]),
            ),
          ]),
        ),
      );
    },
  );
  if (picked != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = [picked, ...recent.where((e) => e != picked)].take(32).toList();
      await prefs.setStringList('chat_recent_emojis', next);
    } catch (_) {}
  }
  return picked;
}

// ---------------------------------------------------------------------
// Voice notes
// ---------------------------------------------------------------------
/// The recording bar that replaces the message box while recording.
class _VoiceRecorderBar extends StatefulWidget {
  final void Function(Uint8List bytes, String mime, String name, int seconds) onDone;
  final VoidCallback onCancel;
  const _VoiceRecorderBar({required this.onDone, required this.onCancel});

  @override
  State<_VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<_VoiceRecorderBar> {
  final _rec = AudioRecorder();
  Timer? _ticker;
  int _seconds = 0;
  bool _started = false;
  bool _finishing = false;
  String _mime = 'audio/webm';
  String _ext = 'webm';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        _fail("Allow the microphone to record voice messages.");
        return;
      }
      AudioEncoder enc = AudioEncoder.wav;
      if (await _rec.isEncoderSupported(AudioEncoder.opus)) {
        enc = AudioEncoder.opus;
        _mime = kIsWeb ? 'audio/webm' : 'audio/ogg';
        _ext = kIsWeb ? 'webm' : 'ogg';
      } else if (await _rec.isEncoderSupported(AudioEncoder.aacLc)) {
        enc = AudioEncoder.aacLc;
        _mime = 'audio/mp4';
        _ext = 'm4a';
      } else {
        _mime = 'audio/wav';
        _ext = 'wav';
      }
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$_ext';
      }
      await _rec.start(RecordConfig(encoder: enc, numChannels: 1), path: path);
      if (!mounted) return;
      setState(() => _started = true);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= 600) _finish(); // 10 minutes at most
      });
    } catch (e) {
      debugPrint("Record error: $e");
      _fail("Couldn't start recording on this device.");
    }
  }

  void _fail(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    widget.onCancel();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    try {
      final path = await _rec.stop();
      if (path == null || path.isEmpty || _seconds < 1) {
        widget.onCancel();
        return;
      }
      final bytes = await XFile(path).readAsBytes();
      widget.onDone(bytes, _mime, 'Voice message.$_ext', _seconds);
    } catch (e) {
      debugPrint("Record stop error: $e");
      _fail("The recording couldn't be saved.");
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    try {
      await _rec.cancel();
    } catch (_) {}
    widget.onCancel();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
      child: Row(children: [
        IconButton(tooltip: "Cancel", icon: Icon(Icons.delete_outline_rounded, color: AppPalette.fg(Colors.red.shade600)), onPressed: _cancel),
        const SizedBox(width: 4),
        _Blink(child: Icon(Icons.fiber_manual_record_rounded, color: Colors.red.shade600, size: 16)),
        const SizedBox(width: 8),
        Text(_started ? t : "Starting…", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        Expanded(
          child: Text("Recording voice message…", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppPalette.fg(Colors.grey.shade700), fontSize: 12.5)),
        ),
        CircleAvatar(
          backgroundColor: AppPalette.bg(_kPurple),
          child: IconButton(tooltip: "Send", icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20), onPressed: _started ? _finish : null),
        ),
      ]),
    );
  }
}

class _Blink extends StatefulWidget {
  final Widget child;
  const _Blink({required this.child});
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween<double>(begin: 0.25, end: 1).animate(_c), child: widget.child);
}

/// Plays a voice note (or any audio attachment) inside the bubble.
class _VoicePlayer extends StatefulWidget {
  final String path;
  final bool mine;
  const _VoicePlayer({required this.path, required this.mine});
  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _error = false;

  Future<void> _toggle() async {
    if (_c == null) {
      setState(() => _loading = true);
      final url = await ChatService.fileUrl(widget.path);
      if (url == null) {
        if (mounted) setState(() => _error = true);
        return;
      }
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await c.initialize();
      } catch (_) {
        if (mounted) setState(() => _error = true);
        return;
      }
      c.addListener(() {
        if (!mounted) return;
        if (c.value.position >= c.value.duration && c.value.duration > Duration.zero && !c.value.isPlaying) {
          c.seekTo(Duration.zero);
        }
        setState(() {});
      });
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _loading = false;
      });
    }
    final c = _c!;
    c.value.isPlaying ? await c.pause() : await c.play();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final playing = c?.value.isPlaying ?? false;
    final dur = c?.value.duration ?? Duration.zero;
    final pos = c?.value.position ?? Duration.zero;
    final frac = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 230,
      child: Row(children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: _error ? null : _toggle,
          child: CircleAvatar(
            radius: 20,
            backgroundColor: AppPalette.bg(_kPurple),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_error ? Icons.error_outline : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded), color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // simple wave look
            SizedBox(
              height: 22,
              child: LayoutBuilder(builder: (context, box) {
                const bars = 28;
                return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  for (int i = 0; i < bars; i++)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2.5,
                          height: 5 + ((i * 7919) % 13).toDouble(),
                          decoration: BoxDecoration(
                            color: AppPalette.fg(i / bars <= frac ? _kPurple : Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ]);
              }),
            ),
            Text(_error ? "Can't play here" : (c == null ? "Voice message" : "${_fmt(pos)} / ${_fmt(dur)}"),
                style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700))),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// Video notes (round video, up to 60 s)
// ---------------------------------------------------------------------
Future<(Uint8List, String, String)?> _recordVideoNote(BuildContext context) =>
    showDialog<(Uint8List, String, String)>(context: context, barrierDismissible: false, builder: (_) => const _VideoNoteRecorder());

class _VideoNoteRecorder extends StatefulWidget {
  const _VideoNoteRecorder();
  @override
  State<_VideoNoteRecorder> createState() => _VideoNoteRecorderState();
}

class _VideoNoteRecorderState extends State<_VideoNoteRecorder> {
  CameraController? _cam;
  List<CameraDescription> _cams = [];
  bool _recording = false;
  int _seconds = 0;
  Timer? _ticker;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init({CameraLensDirection prefer = CameraLensDirection.front}) async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _error = "No camera found.");
        return;
      }
      final cam = _cams.firstWhere((c) => c.lensDirection == prefer, orElse: () => _cams.first);
      final c = CameraController(cam, ResolutionPreset.medium, enableAudio: true);
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      final old = _cam;
      setState(() => _cam = c);
      old?.dispose();
    } catch (e) {
      debugPrint("Camera error: $e");
      if (mounted) setState(() => _error = "Allow the camera and microphone to record a video message.");
    }
  }

  Future<void> _toggle() async {
    final c = _cam;
    if (c == null || _busy) return;
    _busy = true;
    try {
      if (!_recording) {
        await c.startVideoRecording();
        setState(() {
          _recording = true;
          _seconds = 0;
        });
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _seconds++);
          if (_seconds >= 60) _toggle();
        });
      } else {
        _ticker?.cancel();
        final f = await c.stopVideoRecording();
        final bytes = await f.readAsBytes();
        final mime = (f.mimeType ?? '').isNotEmpty ? f.mimeType! : (kIsWeb ? 'video/webm' : 'video/mp4');
        final ext = mime.contains('webm') ? 'webm' : (mime.contains('quicktime') ? 'mov' : 'mp4');
        if (mounted) Navigator.pop(context, (bytes, mime.split(';').first, 'Video message.$ext'));
      }
    } catch (e) {
      debugPrint("Video note error: $e");
      if (mounted) setState(() => _error = "Recording failed on this device.");
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _cam;
    const size = 260.0;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Video message", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 14),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _recording ? Colors.red : _kPurple, width: 4)),
            child: ClipOval(
              child: _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
                  : (c == null || !c.value.isInitialized)
                      ? const Center(child: CircularProgressIndicator())
                      : FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: size,
                            height: size / (c.value.aspectRatio == 0 ? 1 : c.value.aspectRatio),
                            child: CameraPreview(c),
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_recording ? "0:${_seconds.toString().padLeft(2, '0')} / 1:00" : "Up to 60 seconds",
              style: TextStyle(color: AppPalette.fg(_recording ? Colors.red.shade700 : Colors.grey.shade700), fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            FloatingActionButton(
              heroTag: null,
              backgroundColor: _recording ? Colors.red : _kPurple,
              onPressed: c == null ? null : _toggle,
              child: Icon(_recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, color: Colors.white),
            ),
            IconButton(
              tooltip: "Switch camera",
              onPressed: _recording || _cams.length < 2
                  ? null
                  : () => _init(prefer: c?.description.lensDirection == CameraLensDirection.front ? CameraLensDirection.back : CameraLensDirection.front),
              icon: const Icon(Icons.cameraswitch_rounded),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// A round video note inside a bubble: tap to play / pause.
class _VideoNotePlayer extends StatefulWidget {
  final String path;
  const _VideoNotePlayer({required this.path});
  @override
  State<_VideoNotePlayer> createState() => _VideoNotePlayerState();
}

class _VideoNotePlayerState extends State<_VideoNotePlayer> {
  VideoPlayerController? _c;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = await ChatService.fileUrl(widget.path);
    if (url == null) {
      if (mounted) setState(() => _error = true);
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
      await c.setLooping(false);
    } catch (_) {
      if (mounted) setState(() => _error = true);
      return;
    }
    c.addListener(() {
      if (mounted) setState(() {});
    });
    if (mounted) {
      setState(() => _c = c);
    } else {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 200.0;
    final c = _c;
    final playing = c?.value.isPlaying ?? false;
    final dur = c?.value.duration ?? Duration.zero;
    final pos = c?.value.position ?? Duration.zero;
    return GestureDetector(
      onTap: c == null
          ? null
          : () {
              if (playing) {
                c.pause();
              } else {
                if (pos >= dur && dur > Duration.zero) c.seekTo(Duration.zero);
                c.play();
              }
            },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          ClipOval(
            child: Container(
              width: size,
              height: size,
              color: Colors.black12,
              child: _error
                  ? const Icon(Icons.videocam_off_outlined, size: 40)
                  : c == null
                      ? const Center(child: CircularProgressIndicator())
                      : FittedBox(fit: BoxFit.cover, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))),
            ),
          ),
          if (c != null)
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: dur.inMilliseconds == 0 ? 0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0),
                strokeWidth: 3,
                color: _kPurple,
                backgroundColor: Colors.white54,
              ),
            ),
          if (c != null && !playing) const CircleAvatar(radius: 22, backgroundColor: Colors.black45, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28)),
          if (c != null)
            Positioned(
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                child: Text("0:${((playing ? pos : dur).inSeconds).toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Polls
// ---------------------------------------------------------------------
class _PollDraft {
  final String question;
  final List<String> options;
  final bool multiple, anonymous;
  const _PollDraft(this.question, this.options, this.multiple, this.anonymous);
}

class _PollCreator extends StatefulWidget {
  const _PollCreator();
  @override
  State<_PollCreator> createState() => _PollCreatorState();
}

class _PollCreatorState extends State<_PollCreator> {
  final _q = TextEditingController();
  final List<TextEditingController> _opts = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _anonymous = false;

  @override
  void dispose() {
    _q.dispose();
    for (final o in _opts) {
      o.dispose();
    }
    super.dispose();
  }

  bool get _valid => _q.text.trim().isNotEmpty && _opts.where((o) => o.text.trim().isNotEmpty).length >= 2;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        Icon(Icons.poll_outlined, color: AppPalette.fg(_kPurple)),
        const SizedBox(width: 8),
        Text("New poll", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17)),
      ]),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _q,
              autofocus: true,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: "Question", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Text("Options", style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[700]))),
            const SizedBox(height: 6),
            for (int i = 0; i < _opts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _opts[i],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(isDense: true, hintText: "Option ${i + 1}", border: const OutlineInputBorder()),
                    ),
                  ),
                  if (_opts.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: () => setState(() => _opts.removeAt(i).dispose()),
                    ),
                ]),
              ),
            if (_opts.length < 12)
              TextButton.icon(onPressed: () => setState(() => _opts.add(TextEditingController())), icon: const Icon(Icons.add), label: const Text("Add an option")),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Allow several answers"),
              value: _multiple,
              onChanged: (v) => setState(() => _multiple = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Anonymous voting"),
              subtitle: const Text("Nobody sees who voted for what"),
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: Colors.white),
          onPressed: !_valid
              ? null
              : () => Navigator.pop(
                    context,
                    _PollDraft(_q.text.trim(), _opts.map((o) => o.text.trim()).where((t) => t.isNotEmpty).toList(), _multiple, _anonymous),
                  ),
          child: const Text("Create poll"),
        ),
      ],
    );
  }
}

class _PollCard extends StatefulWidget {
  final ChatMessage message;
  final int tick; // bumps when someone votes
  const _PollCard({super.key, required this.message, required this.tick});
  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard> {
  Map<String, dynamic>? _poll;
  List<Map<String, dynamic>> _results = [];
  final Set<int> _pending = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PollCard old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) _load();
  }

  Future<void> _load() async {
    try {
      final p = _poll ?? await ChatService.poll(widget.message.id);
      final r = await ChatService.pollResults(widget.message.id);
      if (!mounted) return;
      setState(() {
        _poll = p;
        _results = r;
      });
    } catch (e) {
      debugPrint("Poll error: $e");
    }
  }

  List<String> get _options => ((_poll?['options'] as List?) ?? const []).map((e) => e.toString()).toList();
  bool get _multiple => _poll?['multiple'] == true;
  bool get _closed => _poll?['closed'] == true;
  bool get _voted => _results.any((r) => r['mine'] == true);

  Future<void> _vote(List<int> options) async {
    setState(() => _busy = true);
    try {
      await ChatService.vote(widget.message.id, options);
      _pending.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : "Couldn't vote.")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showVoters(int i) {
    final voters = (_results.length > i ? (_results[i]['voters'] as List?) : null)?.map((e) => e.toString()).toList() ?? [];
    if (_poll?['anonymous'] == true) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_options[i]),
        content: voters.isEmpty ? const Text("No votes yet.") : Column(mainAxisSize: MainAxisSize.min, children: [for (final v in voters) ListTile(dense: true, leading: _Avatar(name: v, size: 30), title: Text(v))]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opts = _options;
    final total = _results.fold<int>(0, (a, r) => a + ((r['votes'] as num?)?.toInt() ?? 0));
    final showResults = _voted || _closed;
    final mineCreated = _poll?['created_by']?.toString() == ChatService.myId;
    return SizedBox(
      width: 280,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.poll_rounded, size: 18, color: AppPalette.fg(_kPurple)),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.message.content, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14))),
        ]),
        const SizedBox(height: 2),
        Text(
          [
            _poll?['anonymous'] == true ? "Anonymous poll" : "Public poll",
            if (_multiple) "several answers",
            if (_closed) "closed",
          ].join(' · '),
          style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600)),
        ),
        const SizedBox(height: 8),
        if (_poll == null)
          const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
        else
          for (int i = 0; i < opts.length; i++)
            Builder(builder: (_) {
              final r = i < _results.length ? _results[i] : const <String, dynamic>{};
              final votes = (r['votes'] as num?)?.toInt() ?? 0;
              final mine = r['mine'] == true;
              final pct = total == 0 ? 0.0 : votes / total;
              final picked = _pending.contains(i);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onLongPress: () => _showVoters(i),
                  onTap: _closed || _busy
                      ? null
                      : () {
                          if (_multiple) {
                            setState(() => picked ? _pending.remove(i) : _pending.add(i));
                          } else {
                            _vote([i]);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppPalette.line((mine || picked) ? _kPurple : Colors.grey.shade300)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(
                          _multiple
                              ? ((mine || picked) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                              : ((mine || picked) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                          size: 18,
                          color: AppPalette.fg(_kPurple),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(opts[i], style: const TextStyle(fontSize: 13))),
                        if (showResults) Text("${(pct * 100).round()}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ]),
                      if (showResults) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: pct, minHeight: 5, color: _kPurple, backgroundColor: AppPalette.bg(Colors.grey.shade200)),
                        ),
                      ],
                    ]),
                  ),
                ),
              );
            }),
        Row(children: [
          Expanded(child: Text("$total vote${total == 1 ? '' : 's'}", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700)))),
          if (_multiple && !_closed && _pending.isNotEmpty)
            TextButton(onPressed: _busy ? null : () => _vote(_pending.toList()..sort()), child: const Text("Vote")),
          if (_voted && !_closed)
            TextButton(onPressed: _busy ? null : () => _vote(const []), child: const Text("Retract")),
          if (mineCreated && !_closed)
            TextButton(
              onPressed: () async {
                try {
                  await ChatService.closePoll(widget.message.id);
                  _poll = null;
                  await _load();
                } catch (_) {}
              },
              child: const Text("Close"),
            ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------
(double, double, String)? _parseLocation(String content) {
  final parts = content.split('|');
  final ll = parts.first.split(',');
  if (ll.length != 2) return null;
  final lat = double.tryParse(ll[0].trim()), lng = double.tryParse(ll[1].trim());
  if (lat == null || lng == null) return null;
  return (lat, lng, parts.length > 1 ? parts.sublist(1).join('|') : '');
}

/// A small OpenStreetMap picture centred on the point (no API key needed).
class _MapPreview extends StatelessWidget {
  final double lat, lng;
  final double width, height;
  static const int zoom = 15;
  const _MapPreview({required this.lat, required this.lng, this.width = 260, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final n = math.pow(2, zoom).toDouble();
    final x = (lng + 180) / 360 * n;
    final latR = lat * math.pi / 180;
    final y = (1 - math.log(math.tan(latR) + 1 / math.cos(latR)) / math.pi) / 2 * n;
    final cx = x.floor(), cy = y.floor();
    final px = x * 256, py = y * 256;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(child: Container(color: const Color(0xFFE5E7EB))),
          for (int i = cx - 1; i <= cx + 1; i++)
            for (int j = cy - 1; j <= cy + 1; j++)
              Positioned(
                left: i * 256 - px + width / 2,
                top: j * 256 - py + height / 2,
                width: 256,
                height: 256,
                child: Image.network(
                  'https://tile.openstreetmap.org/$zoom/${((i % n.toInt()) + n.toInt()) % n.toInt()}/$j.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                ),
              ),
          Positioned(left: width / 2 - 16, top: height / 2 - 32, child: const Icon(Icons.location_on_rounded, color: Color(0xFFE11D48), size: 32)),
          Positioned(
            right: 4,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              color: Colors.white70,
              child: const Text("© OpenStreetMap", style: TextStyle(fontSize: 8.5, color: Colors.black87)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final String content;
  const _LocationCard({required this.content});
  @override
  Widget build(BuildContext context) {
    final p = _parseLocation(content);
    if (p == null) return const Text("📍 Location");
    final (lat, lng, label) = p;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _MapPreview(lat: lat, lng: lng),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.place_outlined, size: 16, color: AppPalette.fg(_kPurple)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label.isEmpty ? "Shared location" : label,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ]),
        Text("Tap to open in Maps", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
      ]),
    );
  }
}

/// Gets the current position and asks for an optional place name.
Future<(double, double, String)?> _pickLocation(BuildContext context) async {
  try {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Turn on location to share it.")));
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Allow location access to share where you are.")));
      return null;
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Finding your location…"), duration: Duration(seconds: 2)));
    final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)));
    if (!context.mounted) return null;
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Share your location?"),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _MapPreview(lat: pos.latitude, lng: pos.longitude, width: 280, height: 170),
            const SizedBox(height: 10),
            TextField(controller: label, decoration: const InputDecoration(labelText: "Place name (optional)", border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 4),
            Text("Accuracy about ${pos.accuracy.round()} m", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Send")),
        ],
      ),
    );
    return ok == true ? (pos.latitude, pos.longitude, label.text.trim()) : null;
  } catch (e) {
    debugPrint("Location error: $e");
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't get your location.")));
    return null;
  }
}

// ---------------------------------------------------------------------
// Contacts (saved people, who is online, find and add)
// ---------------------------------------------------------------------
class _ContactsScreen extends StatefulWidget {
  const _ContactsScreen();
  @override
  State<_ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<_ContactsScreen> {
  List<ChatPerson> _contacts = [];
  List<ChatPerson> _found = [];
  bool _loading = true;
  bool _onlineOnly = false;
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await ChatService.myContacts();
      final f = await ChatService.contacts('');
      if (!mounted) return;
      setState(() {
        _contacts = c;
        _found = f.where((p) => !p.isContact).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint("Contacts error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchDirectory(String q) {
    setState(() => _search = q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final f = await ChatService.contacts(q);
        if (mounted && _search == q) setState(() => _found = f.where((p) => !p.isContact).toList());
      } catch (_) {}
    });
  }

  Future<void> _add(ChatPerson p) async {
    final nick = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Add ${p.name}"),
        content: TextField(controller: nick, decoration: const InputDecoration(labelText: "Name in my contacts (optional)", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Add")),
        ],
      ),
    );
    if (ok != true) return;
    await ChatService.saveContact(p.id, nickname: nick.text);
    _load();
  }

  Future<void> _menu(ChatPerson p, Offset pos) => showOfficeMenu(context, pos, [
        OfficeMenuItem("Message", icon: Icons.chat_bubble_outline, onTap: () => Navigator.pop(context, p)),
        if (p.isContact) OfficeMenuItem("Rename", icon: Icons.edit_outlined, onTap: () async {
          final n = await showDialog<String>(context: context, builder: (ctx) {
            final c = TextEditingController(text: p.nickname ?? '');
            return AlertDialog(
              title: const Text("Name in my contacts"),
              content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: p.name, border: const OutlineInputBorder())),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Save"))],
            );
          });
          if (n != null) {
            await ChatService.saveContact(p.id, nickname: n);
            _load();
          }
        }),
        if (p.isContact)
          OfficeMenuItem("Remove from contacts", icon: Icons.person_remove_outlined, onTap: () async {
            await ChatService.removeContact(p.id);
            _load();
          })
        else
          OfficeMenuItem("Add to contacts", icon: Icons.person_add_alt_1_outlined, onTap: () => _add(p)),
        const OfficeMenuItem.divider(),
        OfficeMenuItem("Block", icon: Icons.block, color: Colors.red.shade700, onTap: () async {
          await ChatService.block(p.id);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${p.name} is blocked.")));
        }),
      ]);

  Widget _tile(ChatPerson p) {
    final status = _lastSeenText(online: _isOnline(p.id, p.onlineVisible), visible: p.onlineVisible, lastSeen: p.lastSeen);
    final online = status == 'online';
    return OfficeRightClick(
      longPress: true,
      onMenu: (pos) => _menu(p, pos),
      child: ListTile(
        leading: _PresenceAvatar(name: p.displayName, url: p.avatarUrl, size: 42, userId: p.id, visible: p.onlineVisible),
        title: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [if ((p.username ?? '').isNotEmpty) '@${p.username}', status].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppPalette.fg(online ? const Color(0xFF16A34A) : Colors.grey.shade600), fontSize: 12),
        ),
        trailing: p.isContact
            ? IconButton(tooltip: "Message", icon: Icon(Icons.chat_bubble_outline, color: AppPalette.fg(_kPurple)), onPressed: () => Navigator.pop(context, p))
            : IconButton(tooltip: "Add to contacts", icon: Icon(Icons.person_add_alt_1_outlined, color: AppPalette.fg(_kPurple)), onPressed: () => _add(p)),
        onTap: () => Navigator.pop(context, p),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _onlineNow,
      builder: (context, online, _) {
        final q = _search.trim().toLowerCase();
        var contacts = _contacts.where((p) => q.isEmpty || p.displayName.toLowerCase().contains(q) || (p.username ?? '').toLowerCase().contains(q.replaceFirst('@', ''))).toList();
        // online first, then by name
        contacts.sort((a, b) {
          final ao = _isOnline(a.id, a.onlineVisible) ? 0 : 1, bo = _isOnline(b.id, b.onlineVisible) ? 0 : 1;
          return ao != bo ? ao - bo : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
        if (_onlineOnly) contacts = contacts.where((p) => _isOnline(p.id, p.onlineVisible)).toList();
        final onlineCount = _contacts.where((p) => _isOnline(p.id, p.onlineVisible)).length;
        return Scaffold(
          appBar: AppBar(title: Text("Contacts", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: TextField(
                      onChanged: _searchDirectory,
                      decoration: InputDecoration(
                        hintText: "Search contacts, names or @username",
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        fillColor: AppPalette.bg(_kBg),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(spacing: 6, children: [
                      ChoiceChip(label: Text("All (${_contacts.length})"), selected: !_onlineOnly, onSelected: (_) => setState(() => _onlineOnly = false)),
                      ChoiceChip(
                        avatar: const CircleAvatar(radius: 5, backgroundColor: Color(0xFF22C55E)),
                        label: Text("Online now ($onlineCount)"),
                        selected: _onlineOnly,
                        onSelected: (_) => setState(() => _onlineOnly = true),
                      ),
                    ]),
                  ),
                  if (contacts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_contacts.isEmpty ? "No contacts yet. Add people below." : (_onlineOnly ? "None of your contacts is online right now." : "No contacts match."),
                          textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
                    )
                  else
                    for (final p in contacts) _tile(p),
                  if (!_onlineOnly) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                      child: Text(q.isEmpty ? "People you may know" : "People matching \"$_search\"",
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[700]), fontSize: 12.5)),
                    ),
                    for (final p in _found.take(40)) _tile(p),
                  ],
                  const SizedBox(height: 20),
                ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Settings: profile, privacy (Telegram style), chat settings
// ---------------------------------------------------------------------
class _ChatSettingsScreen extends StatefulWidget {
  const _ChatSettingsScreen();
  @override
  State<_ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<_ChatSettingsScreen> {
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _privacy = {};
  bool _loading = true;
  bool _saving = false;
  final _username = TextEditingController();
  final _bio = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await ChatService.myProfile();
    final pr = await ChatService.privacy();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _privacy = {
        'last_seen': 'everyone',
        'photo': 'everyone',
        'messages': 'everyone',
        'groups': 'everyone',
        'read_receipts': true,
        'typing': true,
        'chat_prefs': _ChatPrefs.toPrefs(),
        ...pr,
      };
      _username.text = (p['username'] ?? '').toString();
      _bio.text = (p['bio'] ?? '').toString();
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final values = Map<String, dynamic>.from(_privacy)
        ..remove('user_id')
        ..remove('updated_at')
        ..['chat_prefs'] = _ChatPrefs.toPrefs();
      await ChatService.savePrivacy(values);
      _ChatPrefs.apply(values);
    } catch (e) {
      _snack("Couldn't save the settings. Ask the admin to run 08_round7.sql.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _choose(String key, String title, List<(String, String)> choices) async {
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final c in choices)
            ListTile(
              leading: Icon(_privacy[key] == c.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: AppPalette.fg(_kPurple)),
              title: Text(c.$2),
              onTap: () => Navigator.pop(ctx, c.$1),
            ),
        ],
      ),
    );
    if (v == null) return;
    setState(() => _privacy[key] = v);
    _save();
  }

  Future<void> _changePhoto() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    if (f.bytes!.length > 5 * 1024 * 1024) {
      _snack("Choose a photo under 5 MB.");
      return;
    }
    try {
      final url = await ChatService.uploadAvatar(f.bytes!, f.name);
      setState(() => _profile['avatar_url'] = url);
      _snack("Profile photo updated.");
    } catch (e) {
      _snack("Couldn't upload the photo. Ask the admin to run 08_round7.sql.");
    }
  }

  Future<void> _saveUsername() async {
    try {
      final u = await ChatService.setUsername(_username.text);
      setState(() => _profile['username'] = u);
      _snack(u == null ? "Username removed." : "Username saved: @$u");
    } catch (e) {
      _snack(e is PostgrestException ? e.message : "Couldn't save the username.");
    }
  }

  Future<void> _blockedList() async {
    final list = await ChatService.blocked();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("Blocked people"),
          content: SizedBox(
            width: 360,
            child: list.isEmpty
                ? const Text("You haven't blocked anyone.")
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final p in List.of(list))
                      ListTile(
                        leading: _Avatar(name: p.name, size: 34),
                        title: Text(p.name),
                        subtitle: (p.username ?? '').isEmpty ? null : Text('@${p.username}'),
                        trailing: TextButton(
                          onPressed: () async {
                            await ChatService.unblock(p.id);
                            setD(() => list.remove(p));
                          },
                          child: const Text("Unblock"),
                        ),
                      ),
                  ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
        ),
      ),
    );
  }

  String _label(String v) => switch (v) { 'contacts' => 'My contacts', 'nobody' => 'Nobody', _ => 'Everybody' };

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple))),
      );

  @override
  Widget build(BuildContext context) {
    const who3 = [('everyone', 'Everybody'), ('contacts', 'My contacts'), ('nobody', 'Nobody')];
    const who2 = [('everyone', 'Everybody'), ('contacts', 'My contacts')];
    final name = (_profile['full_name'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900)),
        actions: [if (_saving) const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Stack(children: [
                      _Avatar(name: name.isEmpty ? '?' : name, url: (_profile['avatar_url'] ?? '').toString(), size: 96),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: AppPalette.bg(_kPurple),
                          child: IconButton(padding: EdgeInsets.zero, tooltip: "Change photo", icon: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 17), onPressed: _changePhoto),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Text(name, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18)),
                  if ((_profile['username'] ?? '').toString().isNotEmpty)
                    Text("@${_profile['username']}", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(_kBlue))),
                  _section("Account"),
                  ListTile(
                    leading: const Icon(Icons.alternate_email_rounded),
                    title: TextField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: "Username", prefixText: "@", hintText: "e.g. john_k", isDense: true),
                      onSubmitted: (_) => _saveUsername(),
                    ),
                    trailing: TextButton(onPressed: _saveUsername, child: const Text("Save")),
                    subtitle: const Text("People can find you by @username. 3–32 letters, numbers or _."),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: TextField(controller: _bio, maxLines: 2, decoration: const InputDecoration(labelText: "Bio", isDense: true)),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await ChatService.setBio(_bio.text.trim());
                          _snack("Bio saved.");
                        } catch (_) {
                          _snack("Couldn't save the bio.");
                        }
                      },
                      child: const Text("Save"),
                    ),
                  ),
                  _section("Privacy and security"),
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text("Last seen & online"),
                    subtitle: Text(_label(_privacy['last_seen'].toString())),
                    onTap: () => _choose('last_seen', "Who can see my last seen time and when I'm online?", who3),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: const Text("Profile photo"),
                    subtitle: Text(_label(_privacy['photo'].toString())),
                    onTap: () => _choose('photo', "Who can see my profile photo?", who3),
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: const Text("Who can message me"),
                    subtitle: Text(_label(_privacy['messages'].toString())),
                    onTap: () => _choose('messages', "Who can start a private chat with me?", who2),
                  ),
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text("Who can add me to groups"),
                    subtitle: Text(_label(_privacy['groups'].toString())),
                    onTap: () => _choose('groups', "Who can add me to groups?", who2),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.done_all_rounded),
                    title: const Text("Read receipts"),
                    subtitle: const Text("When off, you won't see when others read your messages either"),
                    value: _privacy['read_receipts'] != false,
                    onChanged: (v) {
                      setState(() => _privacy['read_receipts'] = v);
                      _save();
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.keyboard_outlined),
                    title: const Text("Show when I'm typing"),
                    value: _privacy['typing'] != false,
                    onChanged: (v) {
                      setState(() => _privacy['typing'] = v);
                      _save();
                    },
                  ),
                  ListTile(leading: const Icon(Icons.block), title: const Text("Blocked people"), onTap: _blockedList),
                  _section("Chat settings"),
                  ListTile(
                    leading: const Icon(Icons.format_size_rounded),
                    title: Text("Message text size (${_ChatPrefs.textSize.round()})"),
                    subtitle: Slider(
                      value: _ChatPrefs.textSize,
                      min: 12,
                      max: 22,
                      divisions: 10,
                      onChanged: (v) => setState(() => _ChatPrefs.textSize = v),
                      onChangeEnd: (_) => _save(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _ChatPrefs.background.copyWith(borderRadius: BorderRadius.circular(12)),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
                          decoration: BoxDecoration(color: AppPalette.bg(_kMine), borderRadius: BorderRadius.circular(14)),
                          child: Text("This is how your messages look 👋", style: GoogleFonts.merriweather(fontSize: _ChatPrefs.textSize)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.wallpaper_rounded),
                    title: const Text("Chat background"),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final e in _ChatPrefs.wallpapers.entries)
                          Tooltip(
                            message: e.value.$1,
                            child: InkWell(
                              onTap: () {
                                setState(() => _ChatPrefs.wallpaper = e.key);
                                _save();
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: e.value.$2),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _ChatPrefs.wallpaper == e.key ? _kPurple : Colors.black26, width: _ChatPrefs.wallpaper == e.key ? 3 : 1),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.keyboard_return_rounded),
                    title: const Text("Send with Enter (computer)"),
                    subtitle: const Text("Shift+Enter makes a new line"),
                    value: _ChatPrefs.enterToSend,
                    onChanged: (v) {
                      setState(() => _ChatPrefs.enterToSend = v);
                      _save();
                    },
                  ),
                  const SizedBox(height: 30),
                ]),
              ),
            ),
    );
  }
}
