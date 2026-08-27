#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint connectivity_status.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'connectivity_status'
  s.version          = '0.1.0'
  s.summary          = "The device's network state as one value, with a metered/unmetered distinction."
  s.description      = <<-DESC
Reads the OS-level metered-network capability (NWPath.isExpensive) behind a
platform channel, so the Dart side can distinguish a metered link from an
unmetered one instead of only online/offline.
                       DESC
  s.homepage         = 'https://github.com/kai-tw/dart-packages/tree/main/packages/connectivity_status'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Kai' => 'wuvincentck505@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'connectivity_status/Sources/connectivity_status/**/*'
  s.dependency 'Flutter'
  # Floor set by this package's own dependency on `log_system`, which pulls
  # in firebase_crashlytics / firebase_core — both require iOS 15 via Swift
  # Package Manager. Declaring a lower floor here would be wrong, not
  # permissive: any consumer resolving fresh hits the same SPM platform
  # conflict this package's own example app did.
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'connectivity_status_privacy' => ['connectivity_status/Sources/connectivity_status/PrivacyInfo.xcprivacy']}
end
