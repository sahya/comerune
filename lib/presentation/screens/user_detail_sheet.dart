import 'package:flutter/material.dart';

import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/utils/elapsed_formatter.dart';
import '../theme/app_theme.dart';

/// Converts a [Color] to its ARGB32 integer representation without using the
/// deprecated `Color.value` getter.
int _colorToARGB32(Color c) =>
    (c.a * 255).round() << 24 |
    (c.r * 255).round() << 16 |
    (c.g * 255).round() << 8 |
    (c.b * 255).round();

/// Predefined color palette entries with Japanese labels for accessibility.
const List<({Color color, String label})> kUserColorPaletteEntries =
    <({Color color, String label})>[
  (color: Color(0xFFE53935), label: '赤'),
  (color: Color(0xFFD81B60), label: 'ピンク'),
  (color: Color(0xFF8E24AA), label: '紫'),
  (color: Color(0xFF3949AB), label: '藍'),
  (color: Color(0xFF1E88E5), label: '青'),
  (color: Color(0xFF00ACC1), label: '水色'),
  (color: Color(0xFF00897B), label: '青緑'),
  (color: Color(0xFF43A047), label: '緑'),
  (color: Color(0xFFFF8F00), label: '琥珀'),
  (color: Color(0xFFFF6D00), label: 'オレンジ'),
  (color: Color(0xFF6D4C41), label: '茶'),
  (color: Color(0xFF546E7A), label: '灰青'),
];

/// Predefined color palette for user comment colors.
List<Color> get kUserColorPalette => kUserColorPaletteEntries
    .map((({Color color, String label}) e) => e.color)
    .toList();

class UserDetailSheet extends StatelessWidget {
  const UserDetailSheet({
    super.key,
    required this.userId,
    this.resolvedUserName,
    required this.allMessages,
    required this.isNgUser,
    required this.onToggleNgUser,
    this.themeMode = AppThemeMode.light,
    this.currentColorValue,
    this.onColorChanged,
    this.onColorRemoved,
    this.nickname,
    this.onNicknameChanged,
    this.onNicknameRemoved,
    this.beginAt,
  });

  final String userId;
  final String? resolvedUserName;
  final List<AppMessage> allMessages;
  final bool isNgUser;
  final VoidCallback onToggleNgUser;
  final AppThemeMode themeMode;

  /// Current custom color value for this user, or null if using default.
  final int? currentColorValue;

  /// Called when the user selects a color from the palette.
  final void Function(int colorValue)? onColorChanged;

  /// Called when the user removes the custom color (resets to default).
  final void Function()? onColorRemoved;

  /// Current nickname (コテハン) for this user, or null if not registered.
  final String? nickname;

  /// Called when the user sets or updates a nickname.
  final void Function(String nickname)? onNicknameChanged;

  /// Called when the user removes the nickname.
  final void Function()? onNicknameRemoved;

  /// Optional broadcast start time used to display elapsed time instead of
  /// wall-clock time in the comment list.
  final DateTime? beginAt;

  @override
  Widget build(BuildContext context) {
    final List<AppMessage> userComments = allMessages
        .where(
          (AppMessage m) => m.userId == userId && m.type == AppMessageType.chat,
        )
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        final AppThemeMode effectiveMode = AppTheme.resolveEffectiveMode(
          themeMode,
          MediaQuery.platformBrightnessOf(context),
        );
        final AppThemeColors themeColors = AppTheme.colorsFor(effectiveMode);
        return Column(
          children: <Widget>[
            _buildHandle(themeColors),
            _buildHeader(context, themeColors),
            if (onNicknameChanged != null) ...<Widget>[
              const Divider(height: 1),
              _NicknameRow(
                key: const Key('user-nickname-row'),
                nickname: nickname,
                onNicknameChanged: onNicknameChanged!,
                onNicknameRemoved: onNicknameRemoved,
              ),
            ],
            if (onColorChanged != null) ...<Widget>[
              const Divider(height: 1),
              _ColorPaletteRow(
                key: const Key('user-color-palette'),
                currentColorValue: currentColorValue,
                onColorChanged: onColorChanged!,
                onColorRemoved: onColorRemoved,
              ),
            ],
            const Divider(height: 1),
            Expanded(
              child: _buildCommentList(
                context,
                userComments,
                scrollController,
                themeColors,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHandle(AppThemeColors themeColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: themeColors.sheetHandleColor,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppThemeColors themeColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.person, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ユーザー詳細',
                  key: const Key('user-detail-title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _NgUserButton(
                key: const Key('ng-user-toggle-button'),
                isNgUser: isNgUser,
                onPressed: onToggleNgUser,
                themeColors: themeColors,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ID: $userId',
            key: const Key('user-detail-id'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (nickname != null)
            Text(
              'コテハン: $nickname',
              key: const Key('user-detail-nickname'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          if (resolvedUserName != null)
            Text(
              '名前: $resolvedUserName',
              key: const Key('user-detail-name'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }

  Widget _buildCommentList(
    BuildContext context,
    List<AppMessage> userComments,
    ScrollController scrollController,
    AppThemeColors themeColors,
  ) {
    if (userComments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'この放送でのコメントはありません',
            key: Key('user-detail-no-comments'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'コメント履歴（${userComments.length}件）',
            key: const Key('user-detail-comment-count'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('user-detail-comment-list'),
            controller: scrollController,
            itemCount: userComments.length,
            itemBuilder: (BuildContext context, int index) {
              final AppMessage message = userComments[index];
              return _UserCommentRow(
                key: Key('user-comment-row-$index'),
                message: message,
                themeColors: themeColors,
                beginAt: beginAt,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NgUserButton extends StatelessWidget {
  const _NgUserButton({
    super.key,
    required this.isNgUser,
    required this.onPressed,
    required this.themeColors,
  });

  final bool isNgUser;
  final VoidCallback onPressed;
  final AppThemeColors themeColors;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        isNgUser ? Icons.person_off : Icons.block,
        size: 16,
        color: isNgUser
            ? themeColors.ngUserActiveColor
            : themeColors.subtleTextColor,
      ),
      label: Text(
        isNgUser ? 'NG解除' : 'NG登録',
        style: TextStyle(
          fontSize: 12,
          color: isNgUser
              ? themeColors.ngUserActiveColor
              : themeColors.subtleTextColor,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _ColorPaletteRow extends StatelessWidget {
  const _ColorPaletteRow({
    super.key,
    required this.currentColorValue,
    required this.onColorChanged,
    this.onColorRemoved,
  });

  final int? currentColorValue;
  final void Function(int colorValue) onColorChanged;
  final void Function()? onColorRemoved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'コメント色',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (currentColorValue != null)
                Semantics(
                  button: true,
                  label: 'コメント色をリセット',
                  child: InkWell(
                    key: const Key('user-color-reset-button'),
                    onTap: onColorRemoved,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        'リセット',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ({Color color, String label}) entry
                  in kUserColorPaletteEntries)
                _ColorCircle(
                  key: Key('user-color-${_colorToARGB32(entry.color)}'),
                  color: entry.color,
                  colorLabel: entry.label,
                  isSelected: currentColorValue == _colorToARGB32(entry.color),
                  onTap: () => onColorChanged(_colorToARGB32(entry.color)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({
    super.key,
    required this.color,
    required this.colorLabel,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final String colorLabel;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isSelected ? '$colorLabel 選択中' : colorLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border:
                isSelected ? Border.all(color: Colors.white, width: 2) : null,
            boxShadow: isSelected
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

class _NicknameRow extends StatelessWidget {
  const _NicknameRow({
    super.key,
    required this.nickname,
    required this.onNicknameChanged,
    this.onNicknameRemoved,
  });

  final String? nickname;
  final void Function(String nickname) onNicknameChanged;
  final void Function()? onNicknameRemoved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.badge, size: 18),
          const SizedBox(width: 8),
          Text(
            'コテハン',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nickname ?? '未登録',
              style: TextStyle(
                fontSize: 13,
                color: nickname != null
                    ? null
                    : Theme.of(context).colorScheme.outline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Semantics(
            button: true,
            label: nickname != null ? 'コテハンを変更' : 'コテハンを登録',
            child: InkWell(
              key: const Key('user-nickname-edit-button'),
              onTap: () => _showEditDialog(context),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  nickname != null ? '変更' : '登録',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          if (nickname != null) ...<Widget>[
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'コテハンを削除',
              child: InkWell(
                key: const Key('user-nickname-remove-button'),
                onTap: onNicknameRemoved,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '削除',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final TextEditingController controller =
        TextEditingController(text: nickname ?? '');

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('コテハン登録'),
          content: TextField(
            key: const Key('user-nickname-dialog-field'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'コテハン',
              hintText: 'ニックネームを入力',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('user-nickname-dialog-save-button'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || result.isEmpty) {
      return;
    }

    onNicknameChanged(result);
  }
}

class _UserCommentRow extends StatelessWidget {
  const _UserCommentRow({
    super.key,
    required this.message,
    required this.themeColors,
    this.beginAt,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final DateTime? beginAt;

  @override
  Widget build(BuildContext context) {
    final String timestamp =
        formatTimestamp(message.timestamp, beginAt: beginAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            timestamp,
            style: TextStyle(
              fontSize: 12,
              color: themeColors.subtleTextColor,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message.content,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
