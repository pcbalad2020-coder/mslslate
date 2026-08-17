import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// ============================================================
//  ١) الهوية البصرية
// ============================================================

class AppColors {
  static const bg = Color(0xFF07070C);
  static const surface = Color(0xFF101019);
  static const surfaceHi = Color(0xFF191926);
  static const accent = Color(0xFF7C5CFF);
  static const accentSoft = Color(0xFF5B44C4);
  static const accent2 = Color(0xFF00D9C0);
  static const danger = Color(0xFFFF4D6D);
  static const line = Color(0x14FFFFFF);
}

const String kAppName = 'مسلسلاتي';
const String kAppVersion = '1.0';

// ============================================================
//  ٢) قائمة المواقع — عدّلها هنا فقط
// ============================================================

class SiteInfo {
  final String name;
  final String url;
  final int colorValue;
  final bool isCustom;
  final List<String> extraHosts;
  final String searchPath;

  /// اجعلها false لمواقعك أنت — تمرّ إعلاناتك وروابطها بلا حجب
  final bool blockAds;

  const SiteInfo({
    required this.name,
    required this.url,
    this.colorValue = 0xFF6C5CE7,
    this.isCustom = false,
    this.extraHosts = const [],
    this.searchPath = '/?s=',
    this.blockAds = true,
  });

  Color get color => Color(colorValue);

  String get host {
    try {
      final h = Uri.parse(url).host.toLowerCase();
      return h.startsWith('www.') ? h.substring(4) : h;
    } catch (_) {
      return '';
    }
  }

  /// النطاق الجذر (albox.co من cinema.albox.co)
  String get rootHost {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    return parts.sublist(parts.length - 2).join('.');
  }

  String get letter => name.trim().isEmpty ? '?' : name.trim()[0];

  String searchUrl(String query) {
    final origin = Uri.tryParse(url)?.origin ?? url;
    return '$origin$searchPath${Uri.encodeComponent(query)}';
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'color': colorValue,
    'searchPath': searchPath,
  };

  factory SiteInfo.fromJson(Map<String, dynamic> j) => SiteInfo(
    name: j['name'] ?? '',
    url: j['url'] ?? '',
    colorValue: j['color'] ?? 0xFF6C5CE7,
    searchPath: j['searchPath'] ?? '/?s=',
    isCustom: true,
  );
}

/// ⬇️⬇️ مواقعك ⬇️⬇️
const List<SiteInfo> kDefaultSites = [
  SiteInfo(name: 'قصة عشق', url: 'https://3iskk.xyz', colorValue: 0xFFE84393),
  SiteInfo(name: 'قرمزي', url: 'https://krmzi.org', colorValue: 0xFFD63031),
  SiteInfo(
    name: 'سينما بوكس',
    url: 'https://cinema.albox.co',
    colorValue: 0xFF0984E3,
    extraHosts: ['albox.co'],
  ),
  SiteInfo(
    name: 'سينمانا',
    url: 'https://cinemana.shabakaty.com/home',
    colorValue: 0xFF00B894,
    // سينمانا تبثّ الفيديو من نطاقات شبكتي الأخرى
    extraHosts: ['shabakaty.com', 'shabakaty.cc', 'cinemana.shabakaty.cc'],
    searchPath: '/search?q=',
  ),
];

// ============================================================
//  ٣) العناصر المحفوظة
// ============================================================

class SavedItem {
  final String title;
  final String url;
  final String siteName;
  final int colorValue;
  final int savedAt;

  const SavedItem({
    required this.title,
    required this.url,
    required this.siteName,
    required this.colorValue,
    required this.savedAt,
  });

  Color get color => Color(colorValue);

  String get timeAgo {
    final diff = DateTime.now().millisecondsSinceEpoch - savedAt;
    final m = diff ~/ 60000;
    if (m < 1) return 'الآن';
    if (m < 60) return 'قبل $m د';
    final h = m ~/ 60;
    if (h < 24) return 'قبل $h س';
    final d = h ~/ 24;
    return 'قبل $d ي';
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'siteName': siteName,
    'color': colorValue,
    'savedAt': savedAt,
  };

  factory SavedItem.fromJson(Map<String, dynamic> j) => SavedItem(
    title: j['title'] ?? '',
    url: j['url'] ?? '',
    siteName: j['siteName'] ?? '',
    colorValue: j['color'] ?? 0xFF6C5CE7,
    savedAt: j['savedAt'] ?? 0,
  );
}

// ============================================================
//  ٤) التخزين
// ============================================================

class Store {
  static const kCustomSites = 'custom_sites_v1';
  static const kFavorites = 'favorites_v1';
  static const kHistory = 'history_v1';
  static const kAllowPrefix = 'allowed_hosts_';

  static Future<List<SavedItem>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeList(String key, List<SavedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  // ---------- المفضلة ----------
  static Future<List<SavedItem>> favorites() => _readList(kFavorites);

  static Future<bool> isFavorite(String url) async {
    final list = await favorites();
    return list.any((e) => e.url == url);
  }

  static Future<bool> toggleFavorite(SavedItem item) async {
    final list = await favorites();
    final idx = list.indexWhere((e) => e.url == item.url);
    if (idx >= 0) {
      list.removeAt(idx);
      await _writeList(kFavorites, list);
      return false;
    }
    list.insert(0, item);
    await _writeList(kFavorites, list);
    return true;
  }

  static Future<void> removeFavorite(String url) async {
    final list = await favorites();
    list.removeWhere((e) => e.url == url);
    await _writeList(kFavorites, list);
  }

  static Future<void> clearFavorites() => _writeList(kFavorites, []);

  // ---------- متابعة المشاهدة ----------
  static Future<List<SavedItem>> history() => _readList(kHistory);

  static Future<void> recordVisit(SavedItem item) async {
    final list = await history();
    list.removeWhere((e) => e.siteName == item.siteName);
    list.insert(0, item);
    if (list.length > 12) list.removeRange(12, list.length);
    await _writeList(kHistory, list);
  }

  static Future<void> removeHistory(String url) async {
    final list = await history();
    list.removeWhere((e) => e.url == url);
    await _writeList(kHistory, list);
  }

  static Future<void> clearHistory() => _writeList(kHistory, []);

  // ---------- النطاقات المسموحة ----------
  static Future<int> allowedHostsCount() async {
    final prefs = await SharedPreferences.getInstance();
    var n = 0;
    for (final k in prefs.getKeys()) {
      if (k.startsWith(kAllowPrefix)) {
        n += (prefs.getStringList(k) ?? []).length;
      }
    }
    return n;
  }

  static Future<void> clearAllowedHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(kAllowPrefix))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  // ---------- المواقع المضافة ----------
  static Future<void> clearCustomSites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kCustomSites);
  }

  // ---------- عمليات البحث السابقة ----------
  static const kRecentSearches = 'recent_searches_v1';

  static Future<List<String>> recentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(kRecentSearches) ?? [];
  }

  static Future<void> addRecentSearch(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(kRecentSearches) ?? [];
    list.remove(q);
    list.insert(0, q);
    if (list.length > 8) list.removeRange(8, list.length);
    await prefs.setStringList(kRecentSearches, list);
  }

  static Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kRecentSearches);
  }
}

// ============================================================
//  ٥) حجب الإعلانات
// ============================================================

const List<String> kAdDomains = [
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'google-analytics.com',
  'adservice.google',
  'amazon-adsystem.com',
  'popads.net',
  'popcash.net',
  'popmyads.com',
  'propellerads.com',
  'propellerclick.com',
  'onclickalgo.com',
  'onclicksuper.com',
  'onclickmega.com',
  'adsterra.com',
  'highperformanceformat.com',
  'profitableratecpm.com',
  'effectiveratecpm.com',
  'exoclick.com',
  'exosrv.com',
  'juicyads.com',
  'hilltopads.net',
  'hilltopads.com',
  'mgid.com',
  'taboola.com',
  'outbrain.com',
  'revcontent.com',
  'yllix.com',
  'adcash.com',
  'clickadu.com',
  'clickaine.com',
  'trafficjunky.net',
  'zedo.com',
  'bidvertiser.com',
  'adnxs.com',
  'adroll.com',
  'criteo.com',
  'pubmatic.com',
  'rubiconproject.com',
  'openx.net',
  'smartadserver.com',
  'sharethrough.com',
  'teads.tv',
  'admaven.com',
  'poweredby.jads.co',
  'a-ads.com',
  'histats.com',
  'statcounter.com',
  'quantserve.com',
  'scorecardresearch.com',
  'moatads.com',
  'servedbyadbutler.com',
  'monetag.com',
  'vidoomy.com',
  'aniview.com',
  'sunmedia.tv',
  'adplayer.pro',
];

/// عناصر الإعلانات التي تُخفى بالـ CSS
const String kAdSelectors =
    '.ad, .ads, .Ad, .adsbygoogle, ins.adsbygoogle, '
    '.ad-container, .ad-wrapper, .ad-banner, .adbox, .ad-box, '
    '.advertisement, .advertising, .banner-ads, .sponsored, '
    '[id^="ad-"], [id^="ads-"], [id*="adcontainer"], '
    '[class*="popup-ad"], [class*="ad-slot"], '
    'iframe[src*="ads"], iframe[src*="doubleclick"], '
    'iframe[src*="googlesyndication"]';

/// حاجب إعلانات بجافاسكربت — بديل ContentBlocker الذي يسقط على بعض الأجهزة.
/// يمنع طلبات الشبكة إلى شبكات الإعلانات، ويحذف عناصرها فور ظهورها،
/// ويخفي حاويات الإعلانات بالـ CSS.
String buildAdBlockJS() {
  final domains = kAdDomains.map((d) => "'$d'").join(',');
  return '''
(function () {
  if (window.__wh_ab) return;
  window.__wh_ab = true;

  var AD = [$domains];

  function isAd(u) {
    if (!u) return false;
    u = String(u).toLowerCase();
    if (u.indexOf('embed') > -1 || u.indexOf('player') > -1 ||
        u.indexOf('stream') > -1 || u.indexOf('.m3u8') > -1) return false;
    for (var i = 0; i < AD.length; i++) {
      if (u.indexOf(AD[i]) > -1) return true;
    }
    return u.indexOf('/ads/') > -1 || u.indexOf('popunder') > -1 ||
           u.indexOf('/adserver') > -1;
  }

  function injectCss() {
    try {
      if (document.getElementById('__wh_css')) return;
      var head = document.head || document.documentElement;
      if (!head) return;
      var s = document.createElement('style');
      s.id = '__wh_css';
      s.textContent = '${kAdSelectors.replaceAll("'", r"\'")}' +
        '{display:none!important;visibility:hidden!important;height:0!important}';
      head.appendChild(s);
    } catch (e) {}
  }
  injectCss();
  document.addEventListener('DOMContentLoaded', injectCss);

  // منع طلبات الشبكة
  var _open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    if (isAd(u)) this.__whBlocked = true;
    return _open.apply(this, arguments);
  };
  var _send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    if (this.__whBlocked) return;
    return _send.apply(this, arguments);
  };

  if (window.fetch) {
    var _fetch = window.fetch;
    window.fetch = function () {
      try {
        var a = arguments[0];
        var u = typeof a === 'string' ? a : (a && a.url);
        if (isAd(u)) return Promise.reject(new Error('blocked'));
      } catch (e) {}
      return _fetch.apply(this, arguments);
    };
  }

  // حذف عناصر الإعلانات
  function scrub(root) {
    try {
      var els = root.querySelectorAll('script[src],iframe[src],img[src],link[href],embed[src]');
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        var u = el.getAttribute('src') || el.getAttribute('href');
        if (isAd(u)) el.remove();
      }
    } catch (e) {}
  }
  scrub(document);

  try {
    var target = document.documentElement || document;
    new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var added = muts[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var n = added[j];
          if (!n || n.nodeType !== 1) continue;
          var u = n.getAttribute ? (n.getAttribute('src') || n.getAttribute('href')) : null;
          if (isAd(u)) { n.remove(); continue; }
          if (n.querySelectorAll) scrub(n);
        }
      }
      injectCss();
    }).observe(target, { childList: true, subtree: true });
  } catch (e) {}
})();
''';
}

// ---------- سكربتات الحماية ----------

const String kAntiPopupJS = r'''
(function () {
  if (window.__wh_guard) return;
  window.__wh_guard = true;

  window.open = function () { return null; };
  window.alert = function () {};
  window.confirm = function () { return false; };
  window.prompt = function () { return null; };
  window.onbeforeunload = null;

  document.addEventListener('click', function (e) {
    var el = e.target;
    while (el && el !== document.body) {
      if (el.tagName === 'A') {
        if (el.target === '_blank') el.removeAttribute('target');
        var href = el.getAttribute('href') || '';
        if (href.indexOf('javascript:') === 0 && href.indexOf('open') > -1) {
          e.preventDefault();
          e.stopPropagation();
        }
        return;
      }
      el = el.parentElement;
    }
  }, true);

  function cleanOverlays() {
    if (!document.body) return;
    var nodes = document.querySelectorAll('div, a, span, ins');
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      var s = window.getComputedStyle(n);
      if ((s.position === 'fixed' || s.position === 'absolute') &&
          parseInt(s.zIndex || '0', 10) > 9000) {
        var r = n.getBoundingClientRect();
        var coversScreen = r.width >= window.innerWidth * 0.85 &&
                           r.height >= window.innerHeight * 0.6;
        var isTransparent = s.backgroundColor === 'rgba(0, 0, 0, 0)' ||
                            parseFloat(s.opacity || '1') < 0.1;
        var hasVideo = n.querySelector('video, iframe[src*="embed"]');
        if (coversScreen && !hasVideo && (isTransparent || n.children.length === 0)) {
          n.remove();
        }
      }
    }
    document.querySelectorAll('a[target="_blank"]').forEach(function (a) {
      a.removeAttribute('target');
    });
    document.body.style.overflow = 'auto';
    document.documentElement.style.overflow = 'auto';
  }

  var count = 0;
  var timer = setInterval(function () {
    cleanOverlays();
    if (++count > 12) clearInterval(timer);
  }, 1200);
})();
''';

/// يعترض طلبات الشبكة داخل الصفحة والإطارات لالتقاط روابط الفيديو
/// (هذا ما يجعل الالتقاط يعمل على iOS أيضاً)
const String kMediaHookJS = r'''
(function () {
  if (window.__wh_media) return;
  window.__wh_media = true;

  function report(u) {
    try {
      if (!u) return;
      u = String(u);
      if (u.indexOf('http') !== 0) return;
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('mediaFound', u);
      }
    } catch (e) {}
  }

  var _open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    report(u);
    return _open.apply(this, arguments);
  };

  if (window.fetch) {
    var _fetch = window.fetch;
    window.fetch = function () {
      try {
        var a = arguments[0];
        report(typeof a === 'string' ? a : (a && a.url));
      } catch (e) {}
      return _fetch.apply(this, arguments);
    };
  }

  setInterval(function () {
    try {
      document.querySelectorAll('video').forEach(function (v) {
        report(v.src);
        report(v.currentSrc);
        v.querySelectorAll('source').forEach(function (s) { report(s.src); });
      });
      // بعض المشغّلات تضع الرابط في سمات مخصّصة
      document.querySelectorAll('[data-src],[data-file],[data-url],[src]')
        .forEach(function (el) {
          report(el.getAttribute('data-src'));
          report(el.getAttribute('data-file'));
          report(el.getAttribute('data-url'));
        });
      // أداء الشبكة يكشف كل الموارد المحمّلة فعلياً
      if (window.performance && performance.getEntriesByType) {
        performance.getEntriesByType('resource').forEach(function (e) {
          report(e.name);
        });
      }
    } catch (e) {}
  }, 2500);
})();
''';

const String kScanMediaNowJS = r'''
(function () {
  try {
    function rep(u) {
      if (!u) return;
      u = String(u);
      if (u.indexOf('http') !== 0) return;
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('mediaFound', u);
      }
    }
    document.querySelectorAll('video').forEach(function (v) {
      rep(v.src); rep(v.currentSrc);
      v.querySelectorAll('source').forEach(function (s) { rep(s.src); });
    });
    document.querySelectorAll('[data-src],[data-file],[data-url]').forEach(function (el) {
      rep(el.getAttribute('data-src'));
      rep(el.getAttribute('data-file'));
      rep(el.getAttribute('data-url'));
    });
    if (window.performance && performance.getEntriesByType) {
      performance.getEntriesByType('resource').forEach(function (e) { rep(e.name); });
    }
  } catch (e) {}
})();
''';

const String kDeepCleanJS = r'''
(function () {
  var killWords = ['ads', 'ad-', 'banner', 'popup', 'sponsor', 'promo'];
  document.querySelectorAll('iframe').forEach(function (f) {
    var src = (f.getAttribute('src') || '').toLowerCase();
    if (src.indexOf('embed') > -1 || src.indexOf('player') > -1 ||
        src.indexOf('stream') > -1 || src.indexOf('video') > -1) return;
    for (var i = 0; i < killWords.length; i++) {
      if (src.indexOf(killWords[i]) > -1) { f.remove(); return; }
    }
  });
  document.querySelectorAll('div, section, aside').forEach(function (n) {
    if (n.querySelector('video, iframe')) return;
    var id = ((n.id || '') + ' ' + (n.className || '')).toString().toLowerCase();
    for (var i = 0; i < killWords.length; i++) {
      if (id.indexOf(killWords[i]) > -1) { n.remove(); return; }
    }
  });
  if (document.body) document.body.style.overflow = 'auto';
})();
''';

// ============================================================
//  ٦) نقطة البداية
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MosalsalatiApp());
}

class MosalsalatiApp extends StatelessWidget {
  const MosalsalatiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.danger,
        surface: AppColors.surface,
      ),
    );

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: base.copyWith(
        textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        dividerColor: AppColors.line,
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surfaceHi,
          contentTextStyle: GoogleFonts.cairo(fontSize: 13),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeScreen(),
    );
  }
}

// ============================================================
//  ٧) الشاشة الرئيسية
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<SiteInfo> _customSites = [];
  List<SavedItem> _history = [];
  List<SavedItem> _favorites = [];
  List<String> _recentSearches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(Store.kCustomSites);
    var custom = <SiteInfo>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        custom = list
            .map((e) => SiteInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    final hist = await Store.history();
    final favs = await Store.favorites();
    final recents = await Store.recentSearches();

    if (!mounted) return;
    setState(() {
      _customSites = custom;
      _history = hist;
      _favorites = favs;
      _recentSearches = recents;
      _loading = false;
    });
  }

  Future<void> _saveCustomSites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      Store.kCustomSites,
      jsonEncode(_customSites.map((e) => e.toJson()).toList()),
    );
  }

  List<SiteInfo> get _allSites => [...kDefaultSites, ..._customSites];

  SiteInfo _siteForName(String name) => _allSites.firstWhere(
    (s) => s.name == name,
    orElse: () => _allSites.first,
  );

  Future<void> _openSite(SiteInfo site, {String? startUrl}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrowserScreen(site: site, startUrl: startUrl),
      ),
    );
    _loadAll();
  }

  void _runSearch([String? preset]) async {
    final q = (preset ?? _searchCtrl.text).trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    await Store.addRecentSearch(q);
    final recents = await Store.recentSearches();
    if (!mounted) return;
    setState(() => _recentSearches = recents);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              Text(
                'البحث عن «$q»',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'اختر الموقع الذي تريد البحث فيه',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 14),
              ..._allSites.map(
                (s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _SiteMark(site: s, size: 40),
                  title: Text(
                    s.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    s.host,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(
                    Icons.chevron_left,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openSite(s, startUrl: s.searchUrl(q));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addSiteDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');
    final searchCtrl = TextEditingController(text: '/?s=');

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('إضافة موقع', style: TextStyle(fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Field(controller: nameCtrl, label: 'اسم الموقع'),
              const SizedBox(height: 12),
              _Field(controller: urlCtrl, label: 'الرابط', ltr: true),
              const SizedBox(height: 12),
              _Field(
                controller: searchCtrl,
                label: 'مسار البحث',
                ltr: true,
                helper: 'غالباً /?s=',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );

    if (added == true) {
      final name = nameCtrl.text.trim();
      var url = urlCtrl.text.trim();
      if (name.isEmpty || url.length < 10) return;
      if (!url.startsWith('http')) url = 'https://$url';

      const colors = [
        0xFFE84393,
        0xFF00B894,
        0xFF0984E3,
        0xFFFDCB6E,
        0xFFE17055,
        0xFF6C5CE7,
      ];
      setState(() {
        _customSites.add(
          SiteInfo(
            name: name,
            url: url,
            colorValue: colors[_customSites.length % colors.length],
            searchPath: searchCtrl.text.trim().isEmpty
                ? '/?s='
                : searchCtrl.text.trim(),
            isCustom: true,
          ),
        );
      });
      await _saveCustomSites();
    }
  }

  Future<void> _removeSite(SiteInfo site) async {
    final ok = await _confirm(
      context,
      title: 'حذف الموقع',
      message: 'حذف «${site.name}» من القائمة؟',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (ok) {
      setState(() => _customSites.remove(site));
      await _saveCustomSites();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                )
              : RefreshIndicator(
                  color: AppColors.accent,
                  backgroundColor: AppColors.surface,
                  onRefresh: _loadAll,
                  child: CustomScrollView(
                    slivers: [
                      // ---------- الترويسة ----------
                      SliverAppBar(
                        pinned: true,
                        expandedHeight: 168,
                        backgroundColor: AppColors.bg,
                        actions: [
                          IconButton(
                            tooltip: 'المفضلة',
                            icon: const Icon(Icons.bookmark_border_rounded),
                            onPressed: _openFavorites,
                          ),
                          IconButton(
                            tooltip: 'الإعدادات',
                            icon: const Icon(Icons.tune_rounded),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                              _loadAll();
                            },
                          ),
                        ],
                        flexibleSpace: FlexibleSpaceBar(
                          titlePadding: const EdgeInsetsDirectional.only(
                            start: 20,
                            bottom: 16,
                          ),
                          title: const Text(
                            kAppName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          background: const _HeroBackground(),
                        ),
                      ),

                      // ---------- البحث ----------
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: TextField(
                            controller: _searchCtrl,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _runSearch(),
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'ابحث عن مسلسل أو فيلم…',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: AppColors.accent,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.arrow_circle_left_outlined,
                                  size: 22,
                                ),
                                onPressed: _runSearch,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                  color: AppColors.line,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                  color: AppColors.accentSoft,
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ---------- عمليات بحث سابقة ----------
                      if (_recentSearches.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ..._recentSearches.map(
                                  (q) => ActionChip(
                                    label: Text(
                                      q,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: AppColors.surface,
                                    side: const BorderSide(
                                      color: AppColors.line,
                                    ),
                                    avatar: const Icon(
                                      Icons.history,
                                      size: 15,
                                      color: AppColors.accentSoft,
                                    ),
                                    onPressed: () {
                                      _searchCtrl.text = q;
                                      _runSearch(q);
                                    },
                                  ),
                                ),
                                ActionChip(
                                  label: const Text(
                                    'مسح',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                  onPressed: () async {
                                    await Store.clearRecentSearches();
                                    if (!mounted) return;
                                    setState(() => _recentSearches = []);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ---------- إعلان Adsterra (Native Banner) ----------
                      const SliverToBoxAdapter(child: _AdsterraNativeBanner()),

                      // ---------- متابعة المشاهدة ----------
                      if (_history.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _SectionHeader(
                            title: 'أكمل من حيث توقفت',
                            actionLabel: 'مسح',
                            onAction: () async {
                              await Store.clearHistory();
                              _loadAll();
                            },
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 112,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: _history.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final item = _history[i];
                                return _SavedCard(
                                  item: item,
                                  onTap: () => _openSite(
                                    _siteForName(item.siteName),
                                    startUrl: item.url,
                                  ),
                                  onLongPress: () async {
                                    await Store.removeHistory(item.url);
                                    _loadAll();
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],

                      // ---------- المفضلة ----------
                      if (_favorites.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _SectionHeader(
                            title: 'المفضلة',
                            actionLabel: 'الكل',
                            onAction: _openFavorites,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 112,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: _favorites.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final item = _favorites[i];
                                return _SavedCard(
                                  item: item,
                                  starred: true,
                                  onTap: () => _openSite(
                                    _siteForName(item.siteName),
                                    startUrl: item.url,
                                  ),
                                  onLongPress: () async {
                                    await Store.removeFavorite(item.url);
                                    _loadAll();
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],

                      // ---------- المواقع ----------
                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: 'المواقع',
                          actionLabel: 'إضافة',
                          onAction: _addSiteDialog,
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        sliver: SliverList.separated(
                          itemCount: _allSites.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final site = _allSites[i];
                            return _SiteBanner(
                              site: site,
                              onTap: () => _openSite(site),
                              onLongPress: site.isCustom
                                  ? () => _removeSite(site)
                                  : null,
                            );
                          },
                        ),
                      ),

                      // ---------- إعلان Adsterra ----------
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: _AdsterraBanner(),
                        ),
                      ),
                    ],
                  ),
                ),
          const Positioned(right: 12, bottom: 12, child: _AdsterraSocialBar()),
        ],
      ),
    );
  }

  Future<void> _openFavorites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FavoritesScreen(
          onOpen: (item) =>
              _openSite(_siteForName(item.siteName), startUrl: item.url),
        ),
      ),
    );
    _loadAll();
  }
}

// ============================================================
//  ٨) عناصر الواجهة المشتركة
// ============================================================

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool ltr;

  const _Field({
    required this.controller,
    required this.label,
    this.helper,
    this.ltr = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textDirection: ltr ? TextDirection.ltr : null,
      keyboardType: ltr ? TextInputType.url : TextInputType.text,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        labelStyle: const TextStyle(fontSize: 13),
        filled: true,
        fillColor: AppColors.surfaceHi,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 8, 12),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
          const Spacer(),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.6),
              ),
              child: Text(actionLabel!, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _SiteMark extends StatelessWidget {
  final SiteInfo site;
  final double size;

  const _SiteMark({required this.site, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [site.color, site.color.withValues(alpha: 0.55)],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(
            color: site.color.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        site.letter,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final SavedItem item;
  final bool starred;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SavedCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.starred = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [item.color.withValues(alpha: 0.22), AppColors.surface],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.title.isEmpty ? item.siteName : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      starred
                          ? Icons.bookmark_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 15,
                      color: starred ? AppColors.accent : item.color,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.siteName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: item.color),
                      ),
                    ),
                    Text(
                      item.timeAgo,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.bg),
        Positioned(
          top: -60,
          right: -40,
          child: Container(
            width: 220,
            height: 220,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x557C5CFF), Color(0x00000000)],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -70,
          left: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x3300D9C0), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SiteBanner extends StatelessWidget {
  final SiteInfo site;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SiteBanner({
    required this.site,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line),
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [site.color.withValues(alpha: 0.32), AppColors.surface],
            ),
          ),
          child: Stack(
            children: [
              // حرف مائي كبير
              Positioned(
                left: -6,
                top: -24,
                child: Text(
                  site.letter,
                  style: TextStyle(
                    fontSize: 110,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            site.color,
                            site.color.withValues(alpha: 0.5),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: site.color.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        site.letter,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            site.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              site.host,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  إعلانات Adsterra
// ============================================================

/// المدة الفاصلة بين إعادة تحميل الإعلانات
const Duration kAdRefreshInterval = Duration(seconds: 30);

class _AdsterraBanner extends StatefulWidget {
  const _AdsterraBanner();

  @override
  State<_AdsterraBanner> createState() => _AdsterraBannerState();
}

class _AdsterraBannerState extends State<_AdsterraBanner> {
  static const double _adWidth = 300;
  static const double _adHeight = 250;

  static const String _html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}</style>
</head>
<body>
<script>
  atOptions = {
    'key' : '9cf4a3bfddb64f45c7fd70b6814f4f2d',
    'format' : 'iframe',
    'height' : 250,
    'width' : 300,
    'params' : {}
  };
</script>
<script src="https://www.highperformanceformat.com/9cf4a3bfddb64f45c7fd70b6814f4f2d/invoke.js"></script>
</body>
</html>
''';

  InAppWebViewController? _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(kAdRefreshInterval, (_) => _controller?.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        width: _adWidth,
        height: _adHeight,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _html,
            baseUrl: WebUri('https://www.highperformanceformat.com/'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: true,
            disableHorizontalScroll: true,
            disableVerticalScroll: true,
            supportZoom: false,
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) => _controller = controller,
        ),
      ),
    );
  }
}

class _AdsterraNativeBanner extends StatefulWidget {
  const _AdsterraNativeBanner();

  @override
  State<_AdsterraNativeBanner> createState() => _AdsterraNativeBannerState();
}

class _AdsterraNativeBannerState extends State<_AdsterraNativeBanner> {
  static const double _height = 280;

  static const String _html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>html,body{margin:0;padding:0;background:transparent}</style>
</head>
<body>
<script async="async" data-cfasync="false" src="https://pl25597818.effectivecpmnetwork.com/060b324f2dc7531a967badf4f06752da/invoke.js"></script>
<div id="container-060b324f2dc7531a967badf4f06752da"></div>
</body>
</html>
''';

  InAppWebViewController? _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(kAdRefreshInterval, (_) => _controller?.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: _height,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _html,
            baseUrl: WebUri('https://pl25597818.effectivecpmnetwork.com/'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: true,
            disableVerticalScroll: true,
            supportZoom: false,
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) => _controller = controller,
        ),
      ),
    );
  }
}

class _AdsterraSocialBar extends StatefulWidget {
  const _AdsterraSocialBar();

  @override
  State<_AdsterraSocialBar> createState() => _AdsterraSocialBarState();
}

class _AdsterraSocialBarState extends State<_AdsterraSocialBar> {
  static const String _html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}</style>
</head>
<body>
<script src="https://pl25597845.effectivecpmnetwork.com/07/e5/ee/07e5eeb0dc54759d2796922a669ddd03.js"></script>
</body>
</html>
''';

  /// يقيس الحجم الفعلي لمحتوى الإعلان ويبلغ فلاتر به
  static const String _sizeReportJS = r'''
(function () {
  function report() {
    try {
      var w = Math.ceil(document.body.scrollWidth);
      var h = Math.ceil(document.body.scrollHeight);
      if (w > 0 && h > 0 && window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onAdSize', w, h);
      }
    } catch (e) {}
  }
  report();
  window.addEventListener('resize', report);
  if (window.ResizeObserver) {
    new ResizeObserver(report).observe(document.body);
  }
  new MutationObserver(report).observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
  });
})();
''';

  InAppWebViewController? _controller;
  Timer? _timer;
  double _width = 72;
  double _height = 72;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(kAdRefreshInterval, (_) => _controller?.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        width: _width,
        height: _height,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _html,
            baseUrl: WebUri('https://pl25597845.effectivecpmnetwork.com/'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: true,
            disableHorizontalScroll: true,
            disableVerticalScroll: true,
            supportZoom: false,
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;
            controller.addJavaScriptHandler(
              handlerName: 'onAdSize',
              callback: (args) {
                if (!mounted || args.length < 2) return;
                final w = (args[0] as num).toDouble();
                final h = (args[1] as num).toDouble();
                if (w == _width && h == _height) return;
                setState(() {
                  _width = w;
                  _height = h;
                });
              },
            );
          },
          onLoadStop: (controller, url) {
            controller.evaluateJavascript(source: _sizeReportJS);
          },
        ),
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool danger = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: Text(message, style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? Colors.red.shade700 : AppColors.accent,
            foregroundColor: danger ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

// ============================================================
//  ٩) شاشة المفضلة
// ============================================================

class FavoritesScreen extends StatefulWidget {
  final void Function(SavedItem) onOpen;
  const FavoritesScreen({super.key, required this.onOpen});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<SavedItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Store.favorites();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _items.isEmpty
          ? _EmptyState(
              icon: Icons.star_border_rounded,
              title: 'لا توجد عناصر محفوظة',
              hint: 'اضغط ⭐ داخل أي صفحة لحفظها هنا',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = _items[i];
                return Dismissible(
                  key: ValueKey(item.url),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    decoration: BoxDecoration(
                      color: Colors.red.shade800,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) async {
                    await Store.removeFavorite(item.url);
                    setState(() => _items.removeAt(i));
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          item.siteName.isEmpty ? '?' : item.siteName[0],
                          style: TextStyle(
                            color: item.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        item.title.isEmpty ? item.url : item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${item.siteName} · ${item.timeAgo}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onOpen(item);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  ١٠) شاشة الإعدادات
// ============================================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _allowedCount = 0;
  int _favCount = 0;
  int _histCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final a = await Store.allowedHostsCount();
    final f = (await Store.favorites()).length;
    final h = (await Store.history()).length;
    if (mounted) {
      setState(() {
        _allowedCount = a;
        _favCount = f;
        _histCount = h;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _clearCookiesAndCache() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
    _toast('تم مسح الكوكيز والكاش');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SettingsSection(title: 'الحجب والخصوصية'),
          _SettingsTile(
            icon: Icons.shield_outlined,
            title: 'مسح النطاقات المسموحة',
            subtitle: _allowedCount == 0
                ? 'لا توجد نطاقات مسموحة'
                : 'مسموح حالياً بـ $_allowedCount نطاق — امسحها لإعادة تفعيل الحجب الكامل',
            danger: _allowedCount > 0,
            onTap: _allowedCount == 0
                ? null
                : () async {
                    final ok = await _confirm(
                      context,
                      title: 'مسح النطاقات المسموحة',
                      message:
                          'سيعود الحجب إلى وضعه الافتراضي، وقد تحتاج السماح بنطاق المشغّل من جديد.',
                      confirmLabel: 'مسح',
                      danger: true,
                    );
                    if (ok) {
                      await Store.clearAllowedHosts();
                      _toast('تم المسح');
                      _refresh();
                    }
                  },
          ),
          _SettingsTile(
            icon: Icons.cookie_outlined,
            title: 'مسح الكوكيز والكاش',
            subtitle: 'يسجّل خروجك من كل المواقع ويحرّر مساحة',
            onTap: () async {
              final ok = await _confirm(
                context,
                title: 'مسح الكوكيز والكاش',
                message: 'سيتم تسجيل الخروج من جميع المواقع.',
                confirmLabel: 'مسح',
                danger: true,
              );
              if (ok) await _clearCookiesAndCache();
            },
          ),

          const _SettingsSection(title: 'البيانات'),
          _SettingsTile(
            icon: Icons.history_rounded,
            title: 'مسح متابعة المشاهدة',
            subtitle: '$_histCount عنصر',
            onTap: _histCount == 0
                ? null
                : () async {
                    await Store.clearHistory();
                    _toast('تم مسح متابعة المشاهدة');
                    _refresh();
                  },
          ),
          _SettingsTile(
            icon: Icons.star_border_rounded,
            title: 'مسح المفضلة',
            subtitle: '$_favCount عنصر',
            onTap: _favCount == 0
                ? null
                : () async {
                    final ok = await _confirm(
                      context,
                      title: 'مسح المفضلة',
                      message: 'سيتم حذف كل العناصر المحفوظة.',
                      confirmLabel: 'مسح',
                      danger: true,
                    );
                    if (ok) {
                      await Store.clearFavorites();
                      _toast('تم مسح المفضلة');
                      _refresh();
                    }
                  },
          ),
          _SettingsTile(
            icon: Icons.delete_sweep_outlined,
            title: 'حذف المواقع المضافة',
            subtitle: 'يحذف المواقع التي أضفتها يدوياً فقط',
            danger: true,
            onTap: () async {
              final ok = await _confirm(
                context,
                title: 'حذف المواقع المضافة',
                message: 'المواقع الأساسية لن تُحذف.',
                confirmLabel: 'حذف',
                danger: true,
              );
              if (ok) {
                await Store.clearCustomSites();
                _toast('تم الحذف');
              }
            },
          ),

          const _SettingsSection(title: 'عن التطبيق'),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 2.5),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      kAppName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'الإصدار $kAppVersion',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  const _SettingsSection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AppColors.accent.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        enabled: enabled,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (danger ? Colors.red : AppColors.accent).withValues(
              alpha: enabled ? 0.14 : 0.06,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            size: 20,
            color: (danger ? Colors.redAccent : AppColors.accent).withValues(
              alpha: enabled ? 1 : 0.35,
            ),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================
//  المشغّل الداخلي
// ============================================================

class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String referer;
  final String userAgent;

  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    required this.referer,
    required this.userAgent,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: {
          'Referer': widget.referer,
          'User-Agent': widget.userAgent,
        },
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _chewie = ChewieController(
          videoPlayerController: c,
          autoPlay: true,
          looping: false,
          allowPlaybackSpeedChanging: true,
          playbackSpeeds: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.accent,
            handleColor: AppColors.accent,
            bufferedColor: Colors.white24,
            backgroundColor: Colors.white12,
          ),
          deviceOrientationsOnEnterFullScreen: const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          deviceOrientationsAfterFullScreen: const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _chewie?.dispose();
    _video?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.title.isEmpty ? 'تشغيل' : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 52,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'تعذّر تشغيل هذا الرابط',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'قد يكون الرابط محميّاً أو يحتاج ترويسات إضافية.\nجرّب «تشغيل خارجي» في VLC.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('رجوع'),
                    ),
                  ],
                ),
              )
            : _chewie != null
            ? Chewie(controller: _chewie!)
            : const CircularProgressIndicator(color: AppColors.accent),
      ),
    );
  }
}

// ============================================================
//  ١١) شاشة التصفح
// ============================================================

class BrowserScreen extends StatefulWidget {
  final SiteInfo site;
  final String? startUrl;

  const BrowserScreen({super.key, required this.site, this.startUrl});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? _controller;

  double _progress = 0;
  bool _isFullscreen = false;
  bool _isFavorite = false;
  int _blockedCount = 0;
  String _currentTitle = '';
  String _currentUrl = '';

  String? _errorText;
  String? _errorDetail;

  /// مؤقّت يكشف فشل التحميل بلا الاعتماد على callbacks الحزمة
  Timer? _loadWatchdog;

  void _startWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 25), () {
      if (!mounted || _progress >= 1.0) return;
      setState(() {
        _errorText = 'الموقع لا يستجيب';
        _errorDetail = 'انتهت مهلة التحميل';
      });
    });
  }

  /// يتحقق أن الصفحة حمّلت محتوى فعلياً بعد اكتمال التحميل
  Future<void> _verifyPageLoaded(InAppWebViewController c) async {
    try {
      final res = await c.evaluateJavascript(
        source: '''
        (function () {
          if (!document.body) return 0;
          var t = (document.body.innerText || '').trim().length;
          var m = document.querySelectorAll('video, iframe, img').length;
          return t + (m * 50);
        })();
      ''',
      );
      final score = res is int ? res : int.tryParse('$res') ?? 1;
      if (score < 5 && mounted) {
        setState(() {
          _errorText = 'الصفحة فارغة';
          _errorDetail = 'قد يكون النطاق تغيّر أو الموقع محجوب';
        });
      }
    } catch (_) {}
  }

  final Set<String> _blockedHosts = {};
  Set<String> _userAllowed = {};
  final Set<String> _mediaUrls = {};
  final Set<String> _trustedThisSession = {};

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';

  String get _allowKey => '${Store.kAllowPrefix}${widget.site.host}';

  late final InAppWebViewSettings _settings = InAppWebViewSettings(
    supportMultipleWindows: false,
    javaScriptCanOpenWindowsAutomatically: false,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
    javaScriptEnabled: true,
    transparentBackground: true,
    userAgent: _ua,
    useHybridComposition: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    cacheEnabled: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    allowsBackForwardNavigationGestures: true,
    allowsLinkPreview: false,
    disableLongPressContextMenuOnLinks: true,
  );

  /// تُحقن في كل الإطارات (بما فيها إطار المشغّل)
  Future<void> _registerUserScripts(InAppWebViewController c) async {
    final scripts = widget.site.blockAds
        ? [buildAdBlockJS(), kMediaHookJS, kAntiPopupJS]
        : [kMediaHookJS];
    for (final src in scripts) {
      try {
        await c.addUserScript(
          userScript: UserScript(
            source: src,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
        );
      } catch (_) {
        // بعض المنصات لا تدعم الحقن في كل الإطارات — نكتفي بالحقن اليدوي لاحقاً
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.startUrl ?? widget.site.url;
    _loadAllowed();
  }

  @override
  void dispose() {
    _loadWatchdog?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------- النطاقات ----------

  Future<void> _loadAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_allowKey) ?? [];
    if (mounted) setState(() => _userAllowed = list.toSet());
  }

  Future<void> _allowHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userAllowed.add(host.toLowerCase());
      _blockedHosts.remove(host);
    });
    await prefs.setStringList(_allowKey, _userAllowed.toList());
    _controller?.reload();
  }

  bool _isAllowedHost(String? host) {
    if (host == null || host.isEmpty) return false;
    final h = host.toLowerCase().replaceFirst('www.', '');
    final base = widget.site.host;
    if (base.isEmpty) return true;
    if (h == base || h.endsWith('.$base')) return true;

    final root = widget.site.rootHost;
    if (h == root || h.endsWith('.$root')) return true;

    for (final e in widget.site.extraHosts) {
      final x = e.toLowerCase();
      if (h == x || h.endsWith('.$x')) return true;
    }
    for (final e in _userAllowed) {
      if (h == e || h.endsWith('.$e')) return true;
    }

    const allowExtras = [
      'youtube.com',
      'youtu.be',
      'ytimg.com',
      'google.com',
      'gstatic.com',
      'googleapis.com',
      'cloudflare.com',
      'jsdelivr.net',
      'cloudfront.net',
      'facebook.com',
      'fbcdn.net',
      'telegram.org',
      't.me',
    ];
    for (final e in allowExtras) {
      if (h == e || h.endsWith('.$e')) return true;
    }
    return false;
  }

  // ---------- الوسائط ----------

  bool _looksLikeMedia(String url) {
    final u = url.toLowerCase();
    if (u.startsWith('blob:') || u.startsWith('data:')) return false;
    const exts = ['.m3u8', '.mpd', '.mp4', '.mkv', '.webm', '.m4v', '.avi'];
    for (final e in exts) {
      if (u.contains(e)) return true;
    }
    return u.contains('/manifest') || u.contains('master.txt');
  }

  void _addMedia(String u) {
    if (u.isEmpty || !_looksLikeMedia(u) || _mediaUrls.contains(u)) return;
    if (mounted) setState(() => _mediaUrls.add(u));
  }

  Future<void> _openInExternalPlayer(String url) async {
    try {
      if (Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'action_view',
          data: url,
          type: 'video/*',
          arguments: {
            'headers': ['Referer', _currentUrl, 'User-Agent', _ua],
            'title': _currentTitle,
            'secure_uri': true,
          },
        );
        await intent.launch();
      } else {
        final vlc = Uri.parse(
          'vlc-x-callback://x-callback-url/stream?url=${Uri.encodeComponent(url)}',
        );
        if (await canLaunchUrl(vlc)) {
          await launchUrl(vlc);
        } else {
          await _copyToClipboard(url, note: 'لم يُعثر على VLC — نُسخ الرابط');
        }
      }
    } catch (_) {
      await _copyToClipboard(url, note: 'تعذّر فتح المشغّل — نُسخ الرابط');
    }
  }

  Future<void> _copyToClipboard(String url, {String? note}) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(note ?? 'نُسخ الرابط')));
  }

  Future<void> _showMediaSheet() async {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> rescan() async {
            final before = _mediaUrls.length;
            await _controller?.evaluateJavascript(source: kScanMediaNowJS);
            await Future.delayed(const Duration(milliseconds: 600));
            setSheetState(() {});
            if (_mediaUrls.length == before && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('لم يُعثر على شيء جديد')),
              );
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SheetHandle(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'روابط الفيديو',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إعادة الفحص',
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: rescan,
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Text(
                    'شغّلها هنا مباشرة أو في VLC / MX Player',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_mediaUrls.isEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Text(
                            'لم يُعثر على رابط بعد.\nشغّل الفيديو بضع ثوانٍ ثم اضغط «إعادة الفحص».',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, height: 1.6),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: rescan,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('إعادة الفحص'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: AppColors.line),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('إغلاق'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: _mediaUrls.map((u) {
                          final isHls = u.toLowerCase().contains('.m3u8');
                          final uri = Uri.tryParse(u);
                          final name = (uri?.pathSegments.isNotEmpty ?? false)
                              ? uri!.pathSegments.last
                              : u;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHi,
                              border: Border.all(color: AppColors.line),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color:
                                      (isHls
                                              ? Colors.orangeAccent
                                              : Colors.tealAccent)
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isHls
                                      ? Icons.stream_rounded
                                      : Icons.movie_creation_outlined,
                                  size: 19,
                                  color: isHls
                                      ? Colors.orangeAccent
                                      : Colors.tealAccent,
                                ),
                              ),
                              title: Text(
                                name.isEmpty ? u : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              subtitle: Text(
                                uri?.host ?? '',
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontSize: 10.5),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'نسخ',
                                    icon: const Icon(Icons.copy, size: 17),
                                    onPressed: () => _copyToClipboard(u),
                                  ),
                                  IconButton(
                                    tooltip: 'مشغّل خارجي',
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _openInExternalPlayer(u);
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'تشغيل هنا',
                                    icon: const Icon(
                                      Icons.play_circle_fill,
                                      color: AppColors.accent,
                                      size: 28,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      Navigator.pop(ctx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PlayerScreen(
                                            url: u,
                                            title: _currentTitle,
                                            referer: _currentUrl,
                                            userAgent: _ua,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- المفضلة والسجل ----------

  SavedItem _buildItem() => SavedItem(
    title: _currentTitle,
    url: _currentUrl,
    siteName: widget.site.name,
    colorValue: widget.site.colorValue,
    savedAt: DateTime.now().millisecondsSinceEpoch,
  );

  Future<void> _toggleFavorite() async {
    if (_currentUrl.isEmpty) return;
    final added = await Store.toggleFavorite(_buildItem());
    if (!mounted) return;
    setState(() => _isFavorite = added);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? 'أُضيف إلى المفضلة' : 'أُزيل من المفضلة')),
    );
  }

  Future<void> _recordVisit() async {
    if (_currentUrl.isEmpty) return;
    final normalized = _currentUrl.replaceAll(RegExp(r'/$'), '');
    if (normalized == widget.site.url.replaceAll(RegExp(r'/$'), '')) return;
    await Store.recordVisit(_buildItem());
  }

  // ---------- أدوات ----------

  Future<void> _deepClean() async {
    await _controller?.evaluateJavascript(source: kDeepCleanJS);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم تنظيف الصفحة')));
  }

  void _showBlockedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'النطاقات المحجوبة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                'إن لم يعمل المشغّل، اسمح بنطاقه من هنا',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 14),
              if (_blockedHosts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 26),
                  child: Text(
                    'لا يوجد شيء محجوب حالياً',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _blockedHosts
                        .map(
                          (h) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHi,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                h,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              trailing: TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.accent,
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _allowHost(h);
                                },
                                child: const Text('السماح'),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'يمكنك التراجع عن أي سماح من: الإعدادات ← مسح النطاقات المسموحة',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _handleBack() async {
    if (_isFullscreen) {
      // لا توجد exitFullscreen على الكونترولر — نخرج عبر واجهة HTML5
      await _controller?.evaluateJavascript(
        source: '''
        (function () {
          if (document.exitFullscreen) document.exitFullscreen();
          else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
          else if (document.webkitCancelFullScreen) document.webkitCancelFullScreen();
          var v = document.querySelector('video');
          if (v && v.webkitExitFullscreen) v.webkitExitFullscreen();
        })();
      ''',
      );
      return false;
    }
    if (_controller != null && await _controller!.canGoBack()) {
      await _controller!.goBack();
      return false;
    }
    await _recordVisit();
    return true;
  }

  // ---------- البناء ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handleBack();
        if (shouldPop && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen ? null : _buildAppBar(),
        body: SafeArea(
          top: !_isFullscreen,
          bottom: !_isFullscreen,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.startUrl ?? widget.site.url),
                ),
                initialSettings: _settings,

                onWebViewCreated: (c) {
                  _controller = c;
                  c.addJavaScriptHandler(
                    handlerName: 'mediaFound',
                    callback: (args) {
                      if (args.isNotEmpty) _addMedia(args.first.toString());
                      return null;
                    },
                  );
                  _registerUserScripts(c);
                },

                onProgressChanged: (c, p) {
                  if (mounted) setState(() => _progress = p / 100);
                },

                onLoadStart: (c, url) {
                  _startWatchdog();
                  if (!mounted) return;
                  setState(() {
                    _progress = 0.05;
                    _errorText = null;
                    _errorDetail = null;
                    _mediaUrls.clear();
                    if (url != null) _currentUrl = url.toString();
                  });
                },

                onLoadStop: (c, url) async {
                  _loadWatchdog?.cancel();
                  if (widget.site.blockAds) {
                    await c.evaluateJavascript(source: buildAdBlockJS());
                    await c.evaluateJavascript(source: kAntiPopupJS);
                  }
                  await c.evaluateJavascript(source: kMediaHookJS);
                  final title = await c.getTitle();
                  final fav = url == null
                      ? false
                      : await Store.isFavorite(url.toString());
                  if (!mounted) return;
                  setState(() {
                    _progress = 1.0;
                    _currentTitle = title ?? '';
                    if (url != null) _currentUrl = url.toString();
                    _isFavorite = fav;
                  });
                  await _recordVisit();
                  await _verifyPageLoaded(c);
                },

                onCreateWindow: (c, action) async => false,

                shouldOverrideUrlLoading: (c, action) async {
                  final uri = action.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;

                  final scheme = uri.scheme.toLowerCase();
                  if (scheme != 'http' && scheme != 'https') {
                    return NavigationActionPolicy.CANCEL;
                  }

                  // مواقعك: لا حجب تحويلات حتى تعمل روابط إعلاناتك
                  if (!widget.site.blockAds) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (!_isAllowedHost(uri.host)) {
                    if (mounted) {
                      setState(() {
                        _blockedCount++;
                        if (uri.host.isNotEmpty) _blockedHosts.add(uri.host);
                      });
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },

                // ---------- الشهادات ----------
                onReceivedServerTrustAuthRequest: (c, challenge) async {
                  final host = challenge.protectionSpace.host;
                  if (_trustedThisSession.contains(host)) {
                    return ServerTrustAuthResponse(
                      action: ServerTrustAuthResponseAction.PROCEED,
                    );
                  }
                  if (!mounted) {
                    return ServerTrustAuthResponse(
                      action: ServerTrustAuthResponseAction.CANCEL,
                    );
                  }
                  final ok = await _confirm(
                    context,
                    title: 'شهادة غير موثوقة',
                    message:
                        'شهادة الأمان لـ $host غير صالحة أو منتهية.\nهل تريد المتابعة رغم ذلك؟',
                    confirmLabel: 'متابعة',
                    danger: true,
                  );
                  if (ok) _trustedThisSession.add(host);
                  return ServerTrustAuthResponse(
                    action: ok
                        ? ServerTrustAuthResponseAction.PROCEED
                        : ServerTrustAuthResponseAction.CANCEL,
                  );
                },

                // ---------- التحميل ----------
                onDownloadStartRequest: (c, req) async {
                  final url = req.url.toString();
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('فُتح رابط التحميل خارج التطبيق'),
                      ),
                    );
                  } catch (_) {
                    await _copyToClipboard(
                      url,
                      note: 'تعذّر بدء التحميل — نُسخ الرابط',
                    );
                  }
                },

                onEnterFullscreen: (c) {
                  WakelockPlus.enable();
                  SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.immersiveSticky,
                  );
                  if (mounted) setState(() => _isFullscreen = true);
                },
                onExitFullscreen: (c) {
                  WakelockPlus.disable();
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                  if (mounted) setState(() => _isFullscreen = false);
                },
              ),

              if (_errorText != null) _buildErrorView(),
            ],
          ),
        ),
        bottomNavigationBar: _isFullscreen ? null : _buildBottomBar(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.site.name,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          if (_blockedCount > 0)
            Text(
              'حُجب $_blockedCount إعلان',
              style: const TextStyle(fontSize: 10.5, color: Colors.greenAccent),
            )
          else if (_currentTitle.isNotEmpty)
            Text(
              _currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'تشغيل خارجي',
          icon: Badge(
            isLabelVisible: _mediaUrls.isNotEmpty,
            backgroundColor: AppColors.accent,
            textColor: Colors.black,
            label: Text('${_mediaUrls.length}'),
            child: Icon(
              Icons.play_circle_outline,
              color: _mediaUrls.isNotEmpty ? AppColors.accent : null,
            ),
          ),
          onPressed: _showMediaSheet,
        ),
        IconButton(
          tooltip: 'المفضلة',
          icon: Icon(
            _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: _isFavorite ? AppColors.accent : null,
          ),
          onPressed: _toggleFavorite,
        ),
        IconButton(
          tooltip: 'النطاقات المحجوبة',
          icon: Badge(
            isLabelVisible: _blockedHosts.isNotEmpty,
            label: Text('${_blockedHosts.length}'),
            child: const Icon(Icons.shield_outlined),
          ),
          onPressed: _showBlockedSheet,
        ),
        PopupMenuButton<String>(
          color: AppColors.surfaceHi,
          onSelected: (v) {
            switch (v) {
              case 'clean':
                _deepClean();
                break;
              case 'reload':
                _controller?.reload();
                break;
              case 'home':
                _controller?.loadUrl(
                  urlRequest: URLRequest(url: WebUri(widget.site.url)),
                );
                break;
              case 'browser':
                launchUrl(
                  Uri.parse(_currentUrl),
                  mode: LaunchMode.externalApplication,
                );
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'clean',
              child: Row(
                children: [
                  Icon(Icons.cleaning_services_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('تنظيف الصفحة'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'reload',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 10),
                  Text('تحديث'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'home',
              child: Row(
                children: [
                  Icon(Icons.home_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('رئيسية الموقع'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'browser',
              child: Row(
                children: [
                  Icon(Icons.open_in_browser, size: 18),
                  SizedBox(width: 10),
                  Text('فتح في المتصفح'),
                ],
              ),
            ),
          ],
        ),
      ],
      bottom: _progress < 1.0
          ? PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                color: AppColors.accent,
              ),
            )
          : null,
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: AppColors.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _errorText ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _errorDetail ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'تأكد من الاتصال بالإنترنت، أو أن نطاق الموقع لم يتغيّر.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _errorText = null;
                    _errorDetail = null;
                  });
                  _controller?.reload();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onPressed: () => launchUrl(
                  Uri.parse(_currentUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('المتصفح'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomBar() {
    // في الوضع الأفقي نخفيه لتكبير مساحة المشاهدة
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return null;
    }
    return SafeArea(
      child: Container(
        height: 50,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 21),
              tooltip: 'رجوع',
              onPressed: () async {
                if (await _controller?.canGoBack() ?? false) {
                  _controller?.goBack();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 21),
              tooltip: 'تقدّم',
              onPressed: () async {
                if (await _controller?.canGoForward() ?? false) {
                  _controller?.goForward();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.screen_rotation, size: 21),
              tooltip: 'تدوير الشاشة',
              onPressed: () {
                final isPortrait =
                    MediaQuery.of(context).orientation == Orientation.portrait;
                SystemChrome.setPreferredOrientations(
                  isPortrait
                      ? [
                          DeviceOrientation.landscapeLeft,
                          DeviceOrientation.landscapeRight,
                        ]
                      : [
                          DeviceOrientation.portraitUp,
                          DeviceOrientation.portraitDown,
                        ],
                );
                Future.delayed(const Duration(seconds: 2), () {
                  SystemChrome.setPreferredOrientations([
                    DeviceOrientation.portraitUp,
                    DeviceOrientation.portraitDown,
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]);
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.grid_view_rounded, size: 21),
              tooltip: 'كل المواقع',
              onPressed: () async {
                await _recordVisit();
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
