enum TPMStatus {
  supported(0),
  unsupported(1),
  tpmVersionUnsupported(2);

  final int status;

  const TPMStatus(this.status);

  static TPMStatus fromValue(int value) => switch (value) {
    0 => supported,
    1 => unsupported,
    2 => tpmVersionUnsupported,
    _ => throw ArgumentError("Unknown value for TPMStatus: $value"),
  };
}
