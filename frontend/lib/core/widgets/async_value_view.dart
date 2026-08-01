import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mt_error_state.dart';

class AsyncValueView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(BuildContext, T) dataBuilder;
  final Widget Function(BuildContext)? loadingBuilder;
  final Widget Function(BuildContext, Object, StackTrace)? errorBuilder;
  final Widget Function(BuildContext)? emptyBuilder;
  final bool Function(T)? isEmpty;
  final VoidCallback? onRetry;
  final String errorTitle;

  const AsyncValueView({
    super.key,
    required this.value,
    required this.dataBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.isEmpty,
    this.onRetry,
    this.errorTitle = "Couldn't load",
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) {
        if (emptyBuilder != null && isEmpty != null && isEmpty!(data)) {
          return emptyBuilder!(context);
        }
        return dataBuilder(context, data);
      },
      loading: () =>
          loadingBuilder?.call(context) ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      error: (e, st) =>
          errorBuilder?.call(context, e, st) ??
          MtErrorState(
            title: errorTitle,
            message: e.toString(),
            onRetry: onRetry,
          ),
    );
  }
}
