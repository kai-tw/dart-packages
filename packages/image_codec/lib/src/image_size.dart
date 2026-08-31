import 'package:equatable/equatable.dart';

/// An image's pixel dimensions.
///
/// Deliberately free of any `dart:ui` import. This value crosses an isolate
/// boundary in the code that produces it, and a value object that drags the
/// engine's types along is awkward to hand around — the whole point of
/// reading a size without decoding is that the result is a pair of integers,
/// not a live image handle.
class ImageSize extends Equatable {
  const ImageSize({required this.width, required this.height});

  final int width;
  final int height;

  @override
  List<Object?> get props => <Object?>[width, height];
}
