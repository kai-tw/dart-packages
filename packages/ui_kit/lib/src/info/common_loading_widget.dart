import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// A loading indicator, with an optional determinate [progress] (0.0–1.0).
///
/// [title] is required — see the package README §Text ownership.
class CommonLoadingWidget extends StatelessWidget {
  const CommonLoadingWidget({super.key, required this.title, this.progress});

  final String title;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            progress == null ? _buildLoading(context) : _buildProgress(context),
            Text(title),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return LoadingAnimationWidget.staggeredDotsWave(
      color: Theme.of(context).colorScheme.primary,
      size: 50.0,
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: CircularProgressIndicator(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        value: progress,
      ),
    );
  }
}
