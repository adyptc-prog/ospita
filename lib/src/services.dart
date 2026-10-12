part of '../main.dart';

// Servicii native: notificări, SMS, termenul de plată, sincronizare.

// ─── Serviciu notificări push ─────────────────────────────────────────────────
// Notificările sunt programate via AlarmManager nativ (același mecanism ca SMS),
// prin NotifAlarmReceiver.kt — fiabil pe orice versiune Android. Permisiunile
// se cer prin permission_handler.
class NotificationService {
  static const _ch = MethodChannel('pensiune/sms');

  // Păstrată pentru apelanți: nu mai e nimic de inițializat.
  static Future<void> init() async {}

  static Future<void> requestPermissions() async {
    try {
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
    if (_isAndroid) {
      // Android 12: alarmele exacte (remindere, termenul de plată) cer
      // permisiune; de la 13 o acordă USE_EXACT_ALARM din manifest.
      try {
        if (!await Permission.scheduleExactAlarm.isGranted) {
          await Permission.scheduleExactAlarm.request();
        }
      } catch (_) {}
    }

    if (_isAndroid) {
      try {
        final status = await Permission.ignoreBatteryOptimizations.status;
        if (!status.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      } catch (_) {}
    }
  }

  // ID-urile alarmelor includ indexul tabelului (0..9) ca să nu se
  // suprapună între tabele diferite — pentru tabelul 0 (primul, migrat din
  // versiunea cu un singur tabel) formula rămâne identică cu cea veche.
  static Future<void> scheduleFor(Item item, {required int boardIndex}) async {
    if (!_isAndroid) return;
    await cancelFor(item.number, boardIndex: boardIndex);
    final now  = DateTime.now();
    final base = boardIndex * 1000000;

    if (item.warningAt != null &&
        item.warningAt!.isAfter(now) &&
        item.expiresAt != null) {
      await _schedule(
        id: base + item.number * 10 + 1,
        when: item.warningAt!,
        title: tr('⚠️ Alertă: ${item.name}', '⚠️ Alert: ${item.name}'),
        body: tr('Va expira la ${_fmt(item.expiresAt!)}', 'It expires on ${_fmt(item.expiresAt!)}'),
      );
    }
    if (item.expiresAt != null && item.expiresAt!.isAfter(now)) {
      await _schedule(
        id: base + item.number * 10 + 2,
        when: item.expiresAt!,
        title: tr('Sejur încheiat: ${item.name}', 'Stay ended: ${item.name}'),
        body: tr('A venit? Confirmă prezența în aplicație.', 'Did they arrive? Confirm attendance in the app.'),
      );
    }
  }

  static Future<void> cancelFor(int number, {required int boardIndex}) async {
    if (!_isAndroid) return;
    final base = boardIndex * 1000000;
    try {
      await _ch.invokeMethod<void>('cancelNotif', {'id': base + number * 10 + 1});
      await _ch.invokeMethod<void>('cancelNotif', {'id': base + number * 10 + 2});
    } catch (_) {}
  }

  static Future<void> _schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    try {
      await _ch.invokeMethod<void>('scheduleNotif', {
        'id': id,
        'triggerAtMs': when.millisecondsSinceEpoch,
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  static String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// Testele rulează pe desktop — permite simularea Android-ului pentru
// permisiuni și sincronizare (canalele native sunt simulate în teste).
@visibleForTesting
bool? debugSimulateAndroid;
bool get _isAndroid => debugSimulateAndroid ?? Platform.isAndroid;

// ─── Serviciu SMS (alarme programate via Kotlin AlarmManager) ─────────────────
class SmsService {
  static const _ch = MethodChannel('pensiune/sms');

  static bool get isAndroid => _isAndroid;

  // Permission.sms cere împreună SEND_SMS și RECEIVE_SMS (trimitere +
  // sincronizare / rezervări prin SMS).
  static Future<bool> requestPermission() async {
    if (!isAndroid) return true;
    try {
      return (await Permission.sms.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  // Fără permisiune, toate SMS-urile (remindere, rezervări, sincronizare,
  // licență) eșuează silențios în partea nativă — interfața trebuie să știe.
  static Future<bool> hasPermission() async {
    if (!isAndroid) return true;
    try {
      return (await Permission.sms.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  // Ultimul SMS care nu a putut fi trimis (raportul sistemului), neînchis
  // încă de utilizator — sau null.
  static Future<({DateTime failedAt, String phone, String reason})?>
      pendingFailure() async {
    if (!isAndroid) return null;
    try {
      final r = await _ch.invokeMethod<Map<Object?, Object?>>('getSmsFailure');
      if (r == null) return null;
      return (
        failedAt: DateTime.fromMillisecondsSinceEpoch((r['failedAt'] as int?) ?? 0),
        phone: (r['phone'] as String?) ?? '',
        reason: (r['reason'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  // Xiaomi: fără „Pornire automată”, aplicația glisată din Recente nu mai e
  // pornită de sistem pentru SMS-urile primite (botul și sincronizarea tac).
  // true = refuzată; false = permisă, necunoscută sau alt producător.
  static Future<bool> autostartBlocked() async {
    if (!isAndroid) return false;
    try {
      return await _ch.invokeMethod<String>('getAutostartState') == 'denied';
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAutostartSettings() async {
    if (!isAndroid) return;
    try { await _ch.invokeMethod<bool>('openAutostartSettings'); } catch (_) {}
  }

  static Future<void> dismissFailure() async {
    if (!isAndroid) return;
    try { await _ch.invokeMethod<void>('dismissSmsFailure'); } catch (_) {}
  }

  // Trimite un SMS imediat (nu programat) — folosit pentru notificarea
  // clientului la evenimente manuale din aplicație (ex. validarea plății).
  static Future<void> sendNow(String phone, String message) async {
    if (!isAndroid) return;
    try {
      await _ch.invokeMethod<void>('sendSms', {'phone': phone, 'message': message});
    } catch (_) {}
  }

  // ID-urile includ indexul tabelului (0..9) ca să nu se suprapună între
  // tabele diferite — pentru tabelul 0 formula rămâne identică cu cea veche.
  static List<int> _warnIds(int n, int boardIndex) {
    final base = boardIndex * 10000000;
    return [base + n * 100 + 10, base + n * 100 + 11, base + n * 100 + 12];
  }

  static List<int> _expIds(int n, int boardIndex) {
    final base = boardIndex * 10000000;
    return [base + n * 100 + 20, base + n * 100 + 21, base + n * 100 + 22];
  }

  static Future<void> scheduleFor(Item item,
      {String? template, required int boardIndex}) async {
    final tpl = _effectiveSmsTemplate(template);
    if (!isAndroid) return;
    // Așteptăm anularea: altfel ștergerea payload-ului vechi (sms_alarm_<id>)
    // și anularea nativă pot ajunge DUPĂ programarea nouă, sub același id.
    await cancelFor(item.number, boardIndex: boardIndex);
    final phones = item.phones;
    if (phones.isEmpty) return;

    final now       = DateTime.now();
    final expiryStr = item.expiresAt != null ? _fmt(item.expiresAt!) : tr('nesetată', 'not set');
    String buildMsg(String tmpl) => tmpl
        .replaceAll('[NUME]', item.name)
        .replaceAll('[NAME]', item.name)
        .replaceAll('[DATA_EXPIRARE]', expiryStr)
        .replaceAll('[EXPIRY_DATE]', expiryStr);

    if (item.warningAt != null && item.warningAt!.isAfter(now)) {
      final ids = _warnIds(item.number, boardIndex);
      for (var i = 0; i < phones.length && i < ids.length; i++) {
        await _schedule(
            id: ids[i], when: item.warningAt!, phone: phones[i],
            message: buildMsg(tpl));
      }
    }
    if (!item.viaBot && item.expiresAt != null && item.expiresAt!.isAfter(now)) {
      final ids = _expIds(item.number, boardIndex);
      for (var i = 0; i < phones.length && i < ids.length; i++) {
        await _schedule(
            id: ids[i], when: item.expiresAt!, phone: phones[i],
            message: tr('EXPIRAT: ${buildMsg(tpl)}', 'EXPIRED: ${buildMsg(tpl)}'));
      }
    }
  }

  static Future<void> cancelFor(int number, {required int boardIndex}) async {
    if (!isAndroid) return;
    final base = boardIndex * 10000000;
    final ids = [
      ..._warnIds(number, boardIndex), ..._expIds(number, boardIndex),
      base + number * 10 + 3, base + number * 10 + 4,
    ];
    final prefs = await SharedPreferences.getInstance();
    for (final id in ids) {
      try {
        await _ch.invokeMethod<void>('cancel', {'id': id});
      } catch (_) {}
      await prefs.remove('sms_alarm_$id');
    }
  }

  static Future<void> _schedule({
    required int id,
    required DateTime when,
    required String phone,
    required String message,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'sms_alarm_$id', jsonEncode({'phone': phone, 'message': message}));
      await _ch.invokeMethod('schedule', {
        'id': id,
        'triggerAtMs': when.millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  static String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  // Calculul sloturilor libere rulează nativ (Kotlin) pe Android — aceeași
  // sursă de adevăr folosită și de botul de rezervări prin SMS, ca ecranul
  // „Spatiere” să nu poată diverge de ce vede botul. Nu e disponibil pe alte
  // platforme (nu există acces SMS acolo, deci nici bot de rezervat).
  static Future<List<_FreeSlot>> _computeFreeSlots(
    String boardId, {
    int horizonDays = 90,
    int maxResults = 200,
    required int nights,
  }) async {
    if (!Platform.isAndroid) return [];
    try {
      final raw = await _ch.invokeMethod<String>('computeFreeSlots', {
            'boardId': boardId,
            'horizonDays': horizonDays,
            'maxResults': maxResults,
            'nights': nights,
          }) ??
          '[]';
      final decoded = jsonDecode(raw) as List<dynamic>;
      debugPrint('PenDiag: _computeFreeSlots boardId=$boardId rawLen=${raw.length} count=${decoded.length}');
      return decoded.map((e) {
        final m = e as Map<String, dynamic>;
        return _FreeSlot(
          DateTime.fromMillisecondsSinceEpoch(m['s'] as int),
          DateTime.fromMillisecondsSinceEpoch(m['e'] as int),
        );
      }).toList();
    } catch (e, st) {
      debugPrint('PenDiag: _computeFreeSlots FAILED boardId=$boardId error=$e\n$st');
      return [];
    }
  }
}

// ─── Serviciu termen de validare a plății (24h) ─────────────────
// La 24h de la creare, dacă o rezervare nu a fost validată (plată confirmată),
// e ștearsă automat și clientul e anunțat prin SMS — logica de verificare
// rulează nativ (ValidationDeadlineReceiver.kt), independent de Flutter, la
// fel ca restul alarmelor din aplicație (funcționează chiar dacă aplicația nu
// se deschide deloc în acest interval).
class ValidationService {
  static const _ch = MethodChannel('pensiune/sms');

  // Reproduce exact algoritmul java.lang.String.hashCode() — folosit ca ID de
  // alarmă, ca același syncId să dea mereu același ID indiferent dacă
  // rezervarea a fost creată nativ (bot SMS) sau din Flutter (adăugare
  // manuală). Trebuie să rămână identic cu AlarmScheduler.validationAlarmId
  // din partea Kotlin.
  static int _alarmId(String syncId) {
    var h = 0;
    for (final unit in syncId.codeUnits) {
      h = (h * 31 + unit) & 0xFFFFFFFF;
    }
    return h > 0x7FFFFFFF ? h - 0x100000000 : h;
  }

  // Programează (sau reprogramează) termenul de 24h de la crearea itemului.
  // Idempotent — poate fi apelat oricând (adăugare, editare, remerge sync)
  // fără efecte secundare, pentru că termenul se calculează mereu din
  // createdAt, nu din momentul apelului.
  static Future<void> scheduleFor(Item item, String boardId) async {
    if (!_isAndroid) return;
    if (item.validated) {
      await cancelFor(item.syncId);
      return;
    }
    final deadline = item.createdAt.add(const Duration(hours: 24));
    // Termen deja trecut: alarma lui s-a declanșat (sau se va declanșa) deja.
    // O reprogramare acum ar porni-o imediat și ar șterge o rezervare veche
    // (ex. debifarea „validat”, o editare sau orice mesaj de sincronizare).
    if (!deadline.isAfter(DateTime.now())) return;
    final id = _alarmId(item.syncId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('validation_alarm_$id',
          jsonEncode({'board': boardId, 'sync': item.syncId}));
      await _ch.invokeMethod('scheduleValidation', {
        'id': id,
        'triggerAtMs': deadline.millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  static Future<void> cancelFor(String syncId) async {
    if (!_isAndroid) return;
    final id = _alarmId(syncId);
    try {
      await _ch.invokeMethod<void>('cancelValidation', {'id': id});
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('validation_alarm_$id');
  }
}

// ─── Serviciu sincronizare bidirecțională prin SMS ────────────────────────────
//
// Protocol:
//   PEN:A:{json}  — item adăugat
//   PEN:U:{json}  — item actualizat
//   PEN:D:{syncId} — item șters
//   PEN:I:{json}  — item din sincronizare inițială (bulk)
//   PEN:Z:        — sfârșitul sincronizării inițiale
//
// Câmpuri JSON compact: s=syncId, n=name, d=description, c=createdAt,
//   e=expiresAt, w=warningAt, p1/p2/p3=phoneNumbers, st=startsAt,
//   v=validated, b=rezervare prin bot (viaBot),
//   a=prezență ('c' a venit / 'n' nu a venit)
class SyncService {
  static const _ch = MethodChannel('pensiune/sms');
  static String? _partnerPhone;
  static String? _pairingCode;
  static String  _boardId = '';

  static const minCodeLength = 8;

  static bool get isSupported => _isAndroid;
  // Activă doar cu număr ȘI cod de împerechere — fără cod, partenerul ar
  // respinge toate mesajele (sunt semnate).
  static bool get isActive =>
      _partnerPhone != null &&
      _partnerPhone!.isNotEmpty &&
      isValidCode(_pairingCode);
  static String? get partnerPhone => _partnerPhone;
  static String? get pairingCode =>
      _pairingCode == null ? null : formatCode(_pairingCode!);

  // Identic cu SyncAuth.normalizeCode din Kotlin.
  static String normalizeCode(String? code) =>
      (code ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool isValidCode(String? code) =>
      normalizeCode(code).length >= minCodeLength;

  // „K7QM2XPA” → „K7QM-2XPA”, ușor de citit și de tastat pe celălalt telefon.
  static String formatCode(String code) {
    final n = normalizeCode(code);
    final groups = <String>[];
    for (var i = 0; i < n.length; i += 4) {
      groups.add(n.substring(i, min(i + 4, n.length)));
    }
    return groups.join('-');
  }

  // Fără caractere ușor de confundat (0/O, 1/I/L).
  static String generateCode() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return formatCode(
        List.generate(minCodeLength, (_) => alphabet[r.nextInt(alphabet.length)])
            .join());
  }

  // Fiecare tabel are propriul partener de sincronizare — se încarcă la
  // activarea tabelului respectiv.
  static Future<void> load(String boardId) async {
    _boardId = boardId;
    _partnerPhone = null;
    _pairingCode = null;
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    _partnerPhone = prefs.getString(_syncPartnerKeyFor(boardId));
    _pairingCode = prefs.getString(_syncSecretKeyFor(boardId));
  }

  static Future<void> setPartner(String phone, String code) async {
    _partnerPhone = phone.trim();
    _pairingCode = normalizeCode(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncPartnerKeyFor(_boardId), _partnerPhone!);
    await prefs.setString(_syncSecretKeyFor(_boardId), _pairingCode!);
  }

  static Future<void> clearPartner() async {
    _partnerPhone = null;
    _pairingCode = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncPartnerKeyFor(_boardId));
    await prefs.remove(_syncSecretKeyFor(_boardId));
  }

  // Semnarea și trimiterea se fac nativ (SmsSyncReceiver.sendSigned).
  static Future<bool> _sendForBoard(String boardId, String msg) async {
    if (!isSupported) return false;
    try {
      return await _ch.invokeMethod<bool>(
              'sendSync', {'boardId': boardId, 'message': msg}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _send(String msg) async {
    if (!isActive || !isSupported) return;
    await _sendForBoard(_boardId, msg);
  }

  // Trimite toate înregistrările la sincronizarea inițială
  static Future<void> sendInitialSync(List<Item> items) async {
    for (final item in items) {
      await _send('PEN:I:${jsonEncode(item.toSyncJson())}');
      // Pauză între SMS-uri pentru a evita limitele operatorului
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    await _send('PEN:Z:');
  }

  static Future<void> sendAdd(Item item) =>
      _send('PEN:A:${jsonEncode(item.toSyncJson())}');

  static Future<void> sendUpdate(Item item) =>
      _send('PEN:U:${jsonEncode(item.toSyncJson())}');

  static Future<void> sendDelete(String syncId) =>
      _send('PEN:D:$syncId');

  // Licența cumpărată merge pe ambele telefoane sincronizate. La împerechere,
  // telefonul cu licență o trimite („L”), iar cel fără licență o cere („R”) —
  // partenerul poate să-l fi configurat deja pe acesta înainte, caz în care
  // licența trimisă atunci a fost ignorată. Mesajele sunt tratate nativ, în
  // SmsSyncReceiver, doar dacă vin de la partenerul configurat.
  static Future<void> sendLicenseHandshake() async {
    if (!isActive) return;
    // Telefonul cu licență o trimite (dacă are voie); cel fără o cere.
    final status = await LicenseService.shareWithBoard(_boardId);
    if (status == 'no_license') await _send('PEN:R:');
  }

  // Tabelele cu partener și cod de împerechere, câte unul per număr de
  // telefon (același partener pe mai multe tabele primește un singur SMS).
  static Future<List<String>> pairedBoards() async {
    final prefs = await SharedPreferences.getInstance();
    final boards = await _loadOrMigrateBoards(prefs);
    final byPhone = <String, String>{};
    for (final b in boards) {
      final phone = prefs.getString(_syncPartnerKeyFor(b.id))?.trim() ?? '';
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty || !isValidCode(prefs.getString(_syncSecretKeyFor(b.id)))) {
        continue;
      }
      byPhone.putIfAbsent(digits, () => b.id);
    }
    return byPhone.values.toList();
  }

  // Trimite licența partenerilor (nativ refuză un al treilea telefon).
  static Future<LicenseShareOutcome> sendLicenseToAllPartners() async {
    if (!isSupported) return (sent: 0, refused: null);
    var sent = 0;
    String? refused;
    for (final boardId in await pairedBoards()) {
      final status = await LicenseService.shareWithBoard(boardId);
      if (status == 'sent') sent++;
      if (status == 'not_owner' || status == 'other_partner') refused = status;
    }
    return (sent: sent, refused: refused);
  }

  // Fiecare mesaj din coadă e etichetat de partea nativă cu tabelul al cărui
  // partener configurat corespunde expeditorului SMS-ului (boardId poate fi
  // gol dacă a fost primit înainte ca migrarea pe mai multe tabele să ruleze
  // — în acel caz se consideră primul tabel). Fiecare intrare are un id,
  // folosit la confirmare (ackMessages).
  static Future<List<SyncQueueEntry>> getPendingMessages() async {
    if (!isSupported) return [];
    try {
      final raw = await _ch.invokeMethod<String>('getSyncMessages') ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map<SyncQueueEntry?>((e) {
            if (e is! Map) return null;
            final id = e['id'] as String?;
            final msg = e['msg'] as String?;
            if (id == null || id.isEmpty) return null;
            return (
              id: id,
              boardId: (e['board'] as String?) ?? '',
              msg: msg ?? '',
              // Intrările scrise de versiuni vechi nu au „origin” — le
              // tratăm ca venite de la partener (nu le retrimitem).
              fromPartner: e['origin'] != 'local',
              // Trimisă deja partenerului de partea nativă.
              forwarded: e['forwarded'] == true,
            );
          })
          .whereType<SyncQueueEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Trimite partenerului unui anumit tabel (nu neapărat cel activ) — pentru
  // schimbările făcute nativ, cu aplicația închisă, pe orice tabel.
  static Future<void> sendToBoardPartner(String boardId, String msg) =>
      _sendForBoard(boardId, msg);

  // Scoate din coadă doar intrările procesate — nu și pe cele sosite între
  // timp (golirea completă a cozii le pierdea).
  static Future<void> ackMessages(List<String> ids) async {
    if (!isSupported || ids.isEmpty) return;
    try {
      await _ch.invokeMethod<void>('ackSyncMessages', {'ids': ids});
    } catch (_) {}
  }
}
