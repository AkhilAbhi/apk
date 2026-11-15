import 'package:flutter/material.dart';
import '../main.dart';
import '../services/language_settings_service.dart';
import '../theme/app_theme.dart';

class LanguageSelectionScreen extends StatefulWidget {
  final bool isFromSettings;

  const LanguageSelectionScreen({super.key, this.isFromSettings = false});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  AppLanguage _selectedLanguage = LanguageSettingsService.supportedLanguages.first;
  bool _isDownloading = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  Future<void> _loadCurrentLanguage() async {
    final current = await LanguageSettingsService.instance.getSelectedLanguage();
    if (mounted) {
      setState(() {
        _selectedLanguage = current;
      });
    }
  }

  Future<void> _handleStartSetup() async {
    setState(() {
      _isDownloading = true;
      _statusText = 'Initializing language pack...';
    });

    // Friendly delay + real background download
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _statusText = 'Downloading the language...';
      });
    }

    await LanguageSettingsService.instance.setupLanguage(_selectedLanguage);

    if (mounted) {
      setState(() {
        _statusText = 'Ready!';
      });
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      if (widget.isFromSettings) {
        Navigator.pop(context, true);
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationShell(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C29),
      appBar: widget.isFromSettings
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('Voice Input Language'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Header Icon
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.35),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.translate_rounded, color: Colors.white, size: 30),
                ),
              ),
              const SizedBox(height: 20),

              // Title & Subtitle
              const Text(
                'Select your Voice Input Language',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Speak in your native language. All voice transactions are smartly tracked in real-time.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Language Chips / Cards Grid
              Expanded(
                child: ListView.separated(
                  itemCount: LanguageSettingsService.supportedLanguages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final lang = LanguageSettingsService.supportedLanguages[index];
                    final isSelected = lang.code == _selectedLanguage.code;

                    return InkWell(
                      onTap: _isDownloading
                          ? null
                          : () {
                              setState(() {
                                _selectedLanguage = lang;
                              });
                            },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6366F1).withOpacity(0.2)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF2E3E56),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Flag / Language Avatar
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF1E1B4B),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                lang.code.toUpperCase(),
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.primaryLight,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lang.nativeName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    lang.englishName,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1), size: 22)
                            else
                              Icon(Icons.radio_button_off_rounded, color: Colors.white.withOpacity(0.25), size: 22),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Progress Bar if Downloading
              if (_isDownloading) ...[
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFC7D2FE),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0xFF1E1B4B),
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Primary Action Button ("Get Started" or "Set Up Language")
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 6,
                  shadowColor: const Color(0xFF6366F1).withOpacity(0.4),
                ),
                onPressed: _isDownloading ? null : _handleStartSetup,
                child: Text(
                  widget.isFromSettings ? 'Set Up Language' : 'Get Started',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
