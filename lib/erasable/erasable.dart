abstract interface class Erasable {
  /// Returns true if the data has been erased.
  bool get isErased;

  /// Erases the data.
  void erase();
}
