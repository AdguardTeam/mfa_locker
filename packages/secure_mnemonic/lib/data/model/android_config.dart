final class AndroidConfig {
  final String negativeButtonText;
  final String? promptTitle;
  final String? promptSubtitle;
  final String? promptDescription;

  const AndroidConfig({
    required this.negativeButtonText,
    this.promptTitle,
    this.promptSubtitle,
    this.promptDescription,
  });

  factory AndroidConfig.fromMap(Map<String, dynamic> map) => AndroidConfig(
    negativeButtonText: map['negativeButtonText'] ?? '',
    promptTitle: map['promptTitle'],
    promptSubtitle: map['promptSubtitle'],
    promptDescription: map['promptDescription'],
  );

  Map<String, dynamic> toMap() => {
    'negativeButtonText': negativeButtonText,
    'promptTitle': promptTitle,
    'promptSubtitle': promptSubtitle,
    'promptDescription': promptDescription,
  };
}
