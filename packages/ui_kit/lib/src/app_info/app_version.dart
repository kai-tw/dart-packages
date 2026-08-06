import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Load the information app by PackageInfo package.
/// Show the version of this App with the OS logo at left side.
/// It only show the build number in debug mode.
class AppVersion extends StatelessWidget {
  const AppVersion({
    super.key,
    this.iconSize,
    this.iconPadding,
    this.textStyle,
    this.canShowBuildNumber,
  });

  final double? iconSize;
  final EdgeInsets? iconPadding;
  final TextStyle? textStyle;
  final bool? canShowBuildNumber;

  @override
  Widget build(BuildContext context) {
    // Get the OS logo by Platform.
    final IconData osLogo = Platform.isAndroid
        ? Icons.android_rounded
        : Platform.isIOS
        ? Icons.apple_rounded
        : Icons.code_rounded;

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
        if (snapshot.hasData) {
          // The data is ready.
          final String version = snapshot.data!.version;
          final String buildVersion = snapshot.data!.buildNumber;
          final bool canShowBuildNumber = this.canShowBuildNumber ?? kDebugMode;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // The OS logo icon.
              Padding(
                padding: iconPadding ?? const EdgeInsets.only(right: 8.0),
                child: Icon(osLogo, size: iconSize ?? 20.0),
              ),

              // The version text.
              Text(
                'v$version${canShowBuildNumber ? ' ($buildVersion)' : ''}',
                style: textStyle ?? Theme.of(context).textTheme.labelSmall,
              ),
            ],
          );
        } else {
          // The data is not ready. Leave it blank.
          return const SizedBox.shrink();
        }
      },
    );
  }
}
