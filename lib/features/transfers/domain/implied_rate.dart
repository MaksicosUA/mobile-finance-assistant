/// The rate two amounts imply, worked out exactly and shown, never stored.
///
/// A transfer carries what left one wallet and what arrived in the other,
/// because those are the two numbers the person witnessed. No rate travels and
/// none is kept (ADR 0029): it follows from the pair, and a stored copy is a
/// second answer that can disagree with the first.
///
/// Showing it is worth doing anyway — it is how someone notices a zero typed
/// one too many times — so it is derived at the moment of drawing, like a
/// goal's progress and a payment's `due`.
library;

import 'package:flutter/foundation.dart';

/// How many decimal places the shown rate carries.
///
/// Four is what exchange rates are quoted to; it is a display choice and
/// nothing depends on it.
const int impliedRateScale = 4;

@immutable
final class ImpliedRate {
  const ImpliedRate({required this.value, required this.inverse});

  /// One unit of the source currency in the target one.
  final String value;

  /// And the other way round, because people read rates in both directions.
  final String inverse;
}

/// The rate implied by [from] and [to], or null when there is none to state.
///
/// Null rather than zero or a dash: an amount that is missing, unreadable or
/// zero has no rate, and inventing one would be the guess this whole design
/// avoids. Exact throughout — the arithmetic is integer, never floating point,
/// because a number drawn beside money must not drift.
ImpliedRate? impliedRate({required String from, required String to}) {
  final source = _scaled(from);
  final target = _scaled(to);
  if (source == null || target == null) return null;
  if (source.digits == BigInt.zero || target.digits == BigInt.zero) return null;

  return ImpliedRate(
    value: _divide(target, source),
    inverse: _divide(source, target),
  );
}

String _divide(_Scaled numerator, _Scaled denominator) {
  // Bring both to one exponent, then scale the numerator so integer division
  // lands exactly on the requested number of decimal places.
  final exponent = numerator.scale > denominator.scale
      ? numerator.scale
      : denominator.scale;
  final top = numerator.digits * _pow10(exponent - numerator.scale);
  final bottom = denominator.digits * _pow10(exponent - denominator.scale);
  final scaled = (top * _pow10(impliedRateScale)) ~/ bottom;
  final text = scaled.abs().toString().padLeft(impliedRateScale + 1, '0');
  final whole = text.substring(0, text.length - impliedRateScale);
  final fraction = text.substring(text.length - impliedRateScale);
  final sign = scaled.isNegative ? '-' : '';
  return '$sign$whole.$fraction';
}

BigInt _pow10(int exponent) => BigInt.from(10).pow(exponent);

@immutable
final class _Scaled {
  const _Scaled(this.digits, this.scale);

  final BigInt digits;
  final int scale;
}

/// A plain decimal string as integer digits and a decimal exponent.
_Scaled? _scaled(String value) {
  final text = value.trim();
  if (text.isEmpty || text.length > 40) return null;
  final parts = text.split('.');
  if (parts.length > 2) return null;
  final whole = parts.first;
  final fraction = parts.length == 2 ? parts[1] : '';
  if (whole.isEmpty || (parts.length == 2 && fraction.isEmpty)) return null;
  final digits = BigInt.tryParse('$whole$fraction');
  if (digits == null) return null;
  // `tryParse` accepts a leading sign; an amount here is never negative, and a
  // sign would make the shown rate meaningless rather than merely wrong.
  if (digits.isNegative) return null;
  return _Scaled(digits, fraction.length);
}
