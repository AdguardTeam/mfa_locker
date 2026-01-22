enum BiometricStatus {
  supported(0),
  unsupported(1),
  deviceNotPresent(2),
  notConfiguredForUser(3),
  disabledByPolicy(4),
  deviceBusy(5),
  androidBiometricErrorSecurityUpdateRequired(6);

  final int status;

  const BiometricStatus(this.status);

  static BiometricStatus fromValue(int value) => switch (value) {
    0 => supported,
    1 => unsupported,
    2 => deviceNotPresent,
    3 => notConfiguredForUser,
    4 => disabledByPolicy,
    5 => deviceBusy,
    6 => androidBiometricErrorSecurityUpdateRequired,
    _ => throw ArgumentError("Unknown value for BiometricStatus: $value"),
  };
}
