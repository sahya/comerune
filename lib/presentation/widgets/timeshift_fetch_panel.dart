import 'package:flutter/material.dart';

import '../../application/timeshift_fetch/timeshift_fetch_controller.dart';
import '../strings/app_strings.dart';

class TimeshiftFetchPanel extends StatelessWidget {
  const TimeshiftFetchPanel({
    super.key,
    required this.controller,
    required this.onFetch500,
    required this.onFetch1000,
    required this.onFetchAll,
    required this.onCancel,
    required this.onRetry,
  });

  final TimeshiftFetchController controller;
  final VoidCallback onFetch500;
  final VoidCallback onFetch1000;
  final VoidCallback onFetchAll;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return _buildContent(context);
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final TimeshiftFetchStatus status = controller.status;
    final bool isFetching = status == TimeshiftFetchStatus.fetching;
    final bool hasMore = controller.hasMore;
    final int totalFetched = controller.totalFetched;

    if (status == TimeshiftFetchStatus.idle) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildStatusRow(context, status, totalFetched),
          if (isFetching && controller.isFetchingAll)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (isFetching && !controller.isFetchingAll)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(),
            ),
          if (status == TimeshiftFetchStatus.error) _buildErrorRow(context),
          if (hasMore && !isFetching && status != TimeshiftFetchStatus.error)
            _buildFetchButtons(context),
          if (isFetching) _buildCancelButton(context),
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    BuildContext context,
    TimeshiftFetchStatus status,
    int totalFetched,
  ) {
    final String statusText;
    final IconData icon;

    switch (status) {
      case TimeshiftFetchStatus.fetching:
        statusText = AppStrings.timeshift.fetching;
        icon = Icons.downloading;
      case TimeshiftFetchStatus.paused:
        statusText = AppStrings.timeshift.fetchedCount(totalFetched);
        icon = Icons.pause_circle_outline;
      case TimeshiftFetchStatus.completed:
        statusText = AppStrings.timeshift.fetchComplete;
        icon = Icons.check_circle_outline;
      case TimeshiftFetchStatus.error:
        statusText = AppStrings.timeshift.fetchError;
        icon = Icons.error_outline;
      case TimeshiftFetchStatus.idle:
        statusText = '';
        icon = Icons.hourglass_empty;
    }

    return Row(
      children: <Widget>[
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          statusText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        if (totalFetched > 0 && status == TimeshiftFetchStatus.fetching)
          Text(
            AppStrings.timeshift.fetchedCount(totalFetched),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildFetchButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _FetchButton(
              key: const Key('timeshift-fetch-500'),
              label: AppStrings.timeshift.fetch500,
              onPressed: onFetch500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FetchButton(
              key: const Key('timeshift-fetch-1000'),
              label: AppStrings.timeshift.fetch1000,
              onPressed: onFetch1000,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FetchButton(
              key: const Key('timeshift-fetch-all'),
              label: AppStrings.timeshift.fetchAll,
              onPressed: onFetchAll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          key: const Key('timeshift-cancel'),
          onPressed: onCancel,
          child: Text(AppStrings.timeshift.cancel),
        ),
      ),
    );
  }

  Widget _buildErrorRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('timeshift-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(AppStrings.timeshift.retry),
        ),
      ),
    );
  }
}

class _FetchButton extends StatelessWidget {
  const _FetchButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: Theme.of(context).textTheme.labelSmall,
      ),
      child: Text(label),
    );
  }
}
