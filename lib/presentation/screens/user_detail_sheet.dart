import 'package:flutter/material.dart';

import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../theme/app_theme.dart';

class UserDetailSheet extends StatelessWidget {
  const UserDetailSheet({
    super.key,
    required this.userId,
    this.resolvedUserName,
    required this.allMessages,
    required this.isNgUser,
    required this.onToggleNgUser,
    this.themeMode = AppThemeMode.light,
  });

  final String userId;
  final String? resolvedUserName;
  final List<AppMessage> allMessages;
  final bool isNgUser;
  final VoidCallback onToggleNgUser;
  final AppThemeMode themeMode;

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
        final AppThemeColors themeColors = AppTheme.colorsFor(themeMode);
        return Column(
          children: <Widget>[
            _buildHandle(),
            _buildHeader(context, themeColors),
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

  Widget _buildHandle() {
    final AppThemeColors themeColors = AppTheme.colorsFor(themeMode);
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

class _UserCommentRow extends StatelessWidget {
  const _UserCommentRow({
    super.key,
    required this.message,
    required this.themeColors,
  });

  final AppMessage message;
  final AppThemeColors themeColors;

  @override
  Widget build(BuildContext context) {
    final DateTime local = message.timestamp.toLocal();
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    final String ss = local.second.toString().padLeft(2, '0');
    final String timestamp = '$hh:$mm:$ss';

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
