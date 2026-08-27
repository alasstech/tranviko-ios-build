double sanitizedGpsSpeedKmh(double metersPerSecond, {double maxKmh = 135}) {
  if (!metersPerSecond.isFinite || metersPerSecond < 0) return 0;
  final speedKmh = metersPerSecond * 3.6;
  if (!speedKmh.isFinite || speedKmh > maxKmh) return 0;
  return speedKmh;
}

double sanitizedDisplayedSpeedKmh(Object? value, {double maxKmh = 180}) {
  final speed = value is num ? value.toDouble() : double.tryParse('$value');
  if (speed == null || !speed.isFinite || speed < 0 || speed > maxKmh) {
    return 0;
  }
  return speed;
}
