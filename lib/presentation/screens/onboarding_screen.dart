import 'package:flutter/material.dart';

import '../../application/onboarding/onboarding_store.dart';

/// 初回起動時にダイアログとして表示するオンボーディングガイド。
///
/// [barrierDismissible] を false にしているため、最終ページの
/// 「はじめる」ボタンを押さないと閉じられない。
Future<void> showOnboardingDialog({
  required BuildContext context,
  required OnboardingStore onboardingStore,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.white.withValues(alpha: 0.82),
    builder: (BuildContext context) {
      return PopScope(
        canPop: false,
        child: _OnboardingDialog(onboardingStore: onboardingStore),
      );
    },
  );
}

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog({required this.onboardingStore});

  final OnboardingStore onboardingStore;

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;

  static const int _pageCount = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;
    setState(() {
      _isCompleting = true;
    });
    await widget.onboardingStore.markCompleted();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _nextPage() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: 340,
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (int page) {
                      setState(() {
                        _currentPage = page;
                      });
                    },
                    children: <Widget>[
                      _WelcomePage(colorScheme: colorScheme),
                      _CommentViewPage(colorScheme: colorScheme),
                      _SpeechPage(colorScheme: colorScheme),
                      _StartPage(colorScheme: colorScheme),
                    ],
                  ),
                ),
                _PageIndicator(
                  currentPage: _currentPage,
                  pageCount: _pageCount,
                  colorScheme: colorScheme,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: _currentPage == _pageCount - 1
                      ? FilledButton(
                          onPressed: _completeOnboarding,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'はじめる',
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: _nextPage,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'つぎへ',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.currentPage,
    required this.pageCount,
    required this.colorScheme,
  });

  final int currentPage;
  final int pageCount;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ページ ${currentPage + 1} / $pageCount',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(pageCount, (int index) {
          final bool isActive = index == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive
                  ? colorScheme.primary
                  : colorScheme.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// オンボーディングページ
// ---------------------------------------------------------------------------

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      icon: Icons.waving_hand_rounded,
      iconColor: const Color(0xFFFFA726),
      title: 'comerune へようこそ',
      body: 'ニコ生のコメントを\nもっと楽しく、もっと便利に。\n\n'
          'あなたの配信ライフに寄り添う\nコメントビューアです。\n'
          'まずは簡単にご紹介させてください。',
      colorScheme: colorScheme,
    );
  }
}

class _CommentViewPage extends StatelessWidget {
  const _CommentViewPage({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      icon: Icons.chat_bubble_outline_rounded,
      iconColor: const Color(0xFF42A5F5),
      title: 'リアルタイムでコメントを表示',
      body: '放送に届くコメントを\nリアルタイムで見やすく表示します。\n\n'
          'お気に入りユーザーのマークや\n'
          'NGワードで快適な環境を作れます。\n'
          'コメントの統計やログ保存も。',
      colorScheme: colorScheme,
    );
  }
}

class _SpeechPage extends StatelessWidget {
  const _SpeechPage({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      icon: Icons.record_voice_over_rounded,
      iconColor: const Color(0xFF66BB6A),
      title: 'コメントを声で届ける',
      body: '棒読みちゃんや VOICEVOX と連携して、\n'
          'コメントを音声で読み上げます。\n\n'
          '画面から目を離しているときでも\n'
          'リスナーの声を逃さず受け取れます。\n'
          'ニックネームの読み上げにも対応。',
      colorScheme: colorScheme,
    );
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      icon: Icons.rocket_launch_rounded,
      iconColor: const Color(0xFFAB47BC),
      title: '準備完了！',
      body: 'ログインして放送番号を入力すれば\n'
          'すぐにコメントを見られます。\n\n'
          'テーマや色覚モードなど設定も充実。\n'
          'まずは気軽に使ってみてください。\n\n'
          'あなたの配信を応援しています！',
      colorScheme: colorScheme,
    );
  }
}

class _OnboardingPageLayout extends StatelessWidget {
  const _OnboardingPageLayout({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.colorScheme,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: iconColor),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
