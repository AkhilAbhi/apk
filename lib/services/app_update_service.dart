import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

enum UpdateType { minor, major }

class AppUpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String apkUrl;
  final UpdateType type;
  final String filename;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.apkUrl,
    required this.type,
    required this.filename,
  });

  bool get isMajor => type == UpdateType.major;
}

class StorageParsedItem {
  final Reference ref;
  final String filename;
  final UpdateType type;
  final String version;

  const StorageParsedItem({
    required this.ref,
    required this.filename,
    required this.type,
    required this.version,
  });
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._init();
  AppUpdateService._init();

  static const String _prefLastPromptTime = 'last_update_prompt_time';
  static const String _prefLastPromptVersion = 'last_prompted_version';
  static const int _cooldownDurationMs = 24 * 60 * 60 * 1000; // 24 hours

  /// Notifier listened to by the Home AppBar icon for persistent update badge
  final ValueNotifier<AppUpdateInfo?> updateInfoNotifier = ValueNotifier<AppUpdateInfo?>(null);

  bool _isChecking = false;

  /// Strict filename parser for format: [appname]_[type]_v[version].apk
  /// Example: money_minor_v1.0.2.apk, money_major_v2.0.0.apk, aimoneymanager_minor_v1.0.10.apk
  static final RegExp filenameRegex = RegExp(
    r'^.+?_(major|minor)_v?(\d+(?:\.\d+)*)\.apk$',
    caseSensitive: false,
  );

  /// Parses a filename from Firebase Storage. Returns null if pattern does not match.
  static ({UpdateType type, String version})? parseUpdateFilename(String filename) {
    final match = filenameRegex.firstMatch(filename.trim());
    if (match == null) return null;

    final typeStr = match.group(1)?.toLowerCase() ?? 'minor';
    final versionStr = match.group(2)?.trim() ?? '';

    if (versionStr.isEmpty) return null;

    final type = typeStr == 'major' ? UpdateType.major : UpdateType.minor;
    return (type: type, version: versionStr);
  }

  /// Compares two semantic version strings accurately (e.g., 1.0.10 > 1.0.2)
  /// Returns:
  ///   1 if a > b
  ///  -1 if a < b
  ///   0 if a == b
  static int compareVersions(String a, String b) {
    try {
      final aClean = a.split('+').first.trim();
      final bClean = b.split('+').first.trim();

      final aParts = aClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final bParts = bClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
      for (int i = 0; i < maxLen; i++) {
        final partA = i < aParts.length ? aParts[i] : 0;
        final partB = i < bParts.length ? bParts[i] : 0;
        if (partA > partB) return 1;
        if (partA < partB) return -1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Checks if remote version string is strictly newer than current version
  static bool isNewerVersion(String remote, String current) {
    return compareVersions(remote, current) > 0;
  }

  /// Scans Firebase Storage `updates/` folder dynamically and determines if an update is available
  Future<AppUpdateInfo?> checkForUpdate({BuildContext? context}) async {
    if (_isChecking) return updateInfoNotifier.value;
    _isChecking = true;

    try {
      debugPrint('[STORAGE_UPDATE] Scanning Firebase Storage "updates/" folder...');
      final storageRef = FirebaseStorage.instance.ref('updates');
      final listResult = await storageRef.listAll().timeout(const Duration(seconds: 8));

      final List<StorageParsedItem> parsedItems = [];

      for (final item in listResult.items) {
        final parsed = parseUpdateFilename(item.name);
        if (parsed != null) {
          parsedItems.add(
            StorageParsedItem(
              ref: item,
              filename: item.name,
              type: parsed.type,
              version: parsed.version,
            ),
          );
          debugPrint('[STORAGE_UPDATE] Found valid update file: ${item.name} -> type=${parsed.type.name}, version=${parsed.version}');
        } else {
          debugPrint('[STORAGE_UPDATE] Ignoring non-matching file in updates/: ${item.name}');
        }
      }

      if (parsedItems.isEmpty) {
        debugPrint('[STORAGE_UPDATE] No valid update APKs found in updates/');
        updateInfoNotifier.value = null;
        _isChecking = false;
        return null;
      }

      // Sort descending by semantic version so the highest version is first
      parsedItems.sort((a, b) => compareVersions(b.version, a.version));
      final highestItem = parsedItems.first;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('[STORAGE_UPDATE] Current App: v$currentVersion | Highest Remote: v${highestItem.version} (${highestItem.type.name.toUpperCase()})');

      if (isNewerVersion(highestItem.version, currentVersion)) {
        final downloadUrl = await highestItem.ref.getDownloadURL();

        final updateInfo = AppUpdateInfo(
          latestVersion: highestItem.version,
          currentVersion: currentVersion,
          apkUrl: downloadUrl,
          type: highestItem.type,
          filename: highestItem.filename,
        );

        updateInfoNotifier.value = updateInfo;

        if (context != null && context.mounted) {
          if (updateInfo.isMajor) {
            // Major update: ALWAYS prompt immediately (ignore cooldown)
            debugPrint('[STORAGE_UPDATE] Major mandatory update detected. Displaying forced dialog.');
            showUpdateDialog(context, bypassCooldown: true);
          } else {
            // Minor update: Respect 24-hour cooldown
            final shouldPrompt = await _shouldPromptMinorDialog(highestItem.version);
            if (shouldPrompt && context.mounted) {
              debugPrint('[STORAGE_UPDATE] Minor update detected. Prompting dialog.');
              showUpdateDialog(context, bypassCooldown: false);
            } else {
              debugPrint('[STORAGE_UPDATE] Minor update available, but 24-hr cooldown active. Visible in AppBar badge.');
            }
          }
        }

        _isChecking = false;
        return updateInfo;
      } else {
        debugPrint('[STORAGE_UPDATE] App is up to date (v$currentVersion)');
        updateInfoNotifier.value = null;
      }
    } catch (e) {
      debugPrint('[STORAGE_UPDATE] Note: $e');
    } finally {
      _isChecking = false;
    }

    return null;
  }

  /// Checks if 24 hours have passed since last "Later" click on a minor update
  Future<bool> _shouldPromptMinorDialog(String latestVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPromptTime = prefs.getInt(_prefLastPromptTime) ?? 0;
      final lastPromptVersion = prefs.getString(_prefLastPromptVersion) ?? '';

      // First time seeing this version: prompt immediately
      if (lastPromptVersion != latestVersion) {
        return true;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - lastPromptTime;
      return elapsed >= _cooldownDurationMs;
    } catch (_) {
      return true;
    }
  }

  /// Records that user clicked "Later" (or dismissed minor update via back button)
  Future<void> recordLaterTapped(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefLastPromptTime, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_prefLastPromptVersion, version);
      debugPrint('[STORAGE_UPDATE] 24-hour cooldown recorded for v$version');
    } catch (_) {}
  }

  /// Displays the interactive update dialog with PopScope intercept
  void showUpdateDialog(BuildContext context, {bool bypassCooldown = false}) {
    final info = updateInfoNotifier.value;
    if (info == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppUpdateDialog(info: info),
    );
  }
}

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const AppUpdateDialog({super.key, required this.info});

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = '';
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = 'Connecting to Firebase Storage...';
    });

    _cancelToken = CancelToken();

    try {
      final tempDir = await getTemporaryDirectory();
      final apkPath = '${tempDir.path}/${widget.info.filename}';

      final file = File(apkPath);
      if (await file.exists()) {
        await file.delete();
      }

      final dio = Dio();
      await dio.download(
        widget.info.apkUrl,
        apkPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _progress = (received / total).clamp(0.0, 1.0);
              _statusMessage = 'Downloading update... ${(_progress * 100).toInt()}%';
            });
          } else {
            setState(() {
              _statusMessage = 'Downloading (${(received / (1024 * 1024)).toStringAsFixed(1)} MB)...';
            });
          }
        },
      );

      setState(() {
        _progress = 1.0;
        _statusMessage = 'Download complete! Launching installer...';
      });

      debugPrint('[STORAGE_UPDATE] Downloaded to $apkPath. Launching OpenFilex...');

      final result = await OpenFilex.open(
        apkPath,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint('[STORAGE_UPDATE] OpenFilex: ${result.type} - ${result.message}');

      if (mounted) {
        if (!widget.info.isMajor && result.type == ResultType.done) {
          Navigator.pop(context);
        } else {
          setState(() {
            _statusMessage = 'Please complete the installation prompt.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Download failed: $e';
        });
      }
    }
  }

  void _handleBackPress() {
    if (widget.info.isMajor) {
      // Major update: Force app exit on back press
      debugPrint('[STORAGE_UPDATE] Major update back press -> Exiting app');
      SystemNavigator.pop();
    } else {
      // Minor update: Treat back button as "Later" (dismiss & record 24h cooldown)
      debugPrint('[STORAGE_UPDATE] Minor update back press -> Dismissing & recording cooldown');
      AppUpdateService.instance.recordLaterTapped(widget.info.latestVersion);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMajor = widget.info.isMajor;
    final accentColor = isMajor ? const Color(0xFFE5212E) : const Color(0xFF6C63FF);

    return PopScope(
      canPop: false, // We intercept physical back button explicitly
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_isDownloading) {
          _handleBackPress();
        }
      },
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: accentColor.withOpacity(0.5),
            width: isMajor ? 2.0 : 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon Header
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withOpacity(0.18),
                border: Border.all(color: accentColor.withOpacity(0.6), width: 1.5),
              ),
              child: Center(
                child: Icon(
                  isMajor ? Icons.warning_amber_rounded : Icons.system_update_rounded,
                  color: isMajor ? const Color(0xFFE5212E) : AppColors.primaryLight,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              isMajor ? 'Critical Update Required' : 'New Version Available',
              style: TextStyle(
                color: isMajor ? const Color(0xFFE5212E) : AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Version badge chips
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'v${widget.info.currentVersion}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.white54, size: 16),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withOpacity(0.6)),
                  ),
                  child: Text(
                    'v${widget.info.latestVersion}',
                    style: TextStyle(
                      color: isMajor ? const Color(0xFFFF5252) : AppColors.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Description / Alert Message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF161822),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMajor ? const Color(0xFFE5212E).withOpacity(0.3) : Colors.white10,
                ),
              ),
              child: Text(
                isMajor
                    ? 'A critical update is required to continue using the app. Please update now to access your finances safely.'
                    : 'A new update (v${widget.info.latestVersion}) is available with performance improvements and features.',
                style: TextStyle(
                  color: isMajor ? const Color(0xFFFF8A80) : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isMajor ? FontWeight.w500 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 18),

            // Download Progress Bar
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _statusMessage,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ] else if (_statusMessage.isNotEmpty) ...[
              Text(
                _statusMessage,
                style: const TextStyle(color: AppColors.expenseRed, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: _isDownloading
            ? (isMajor
                ? const [] // Forced update: cannot cancel during download
                : [
                    TextButton(
                      onPressed: () {
                        _cancelToken?.cancel();
                        setState(() {
                          _isDownloading = false;
                          _statusMessage = 'Download cancelled';
                        });
                      },
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ])
            : [
                // If minor: Show BOTH "Later" and "Update Now"
                if (!isMajor)
                  TextButton(
                    onPressed: () {
                      AppUpdateService.instance.recordLaterTapped(widget.info.latestVersion);
                      Navigator.pop(context);
                    },
                    child: const Text('Later', style: TextStyle(color: AppColors.textSecondary)),
                  ),

                // "Update Now" button (Only button shown if major)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    isMajor ? 'Install Update' : 'Update Now',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _startDownload,
                ),
              ],
      ),
    );
  }
}
