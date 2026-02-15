---
description: 
auto_execution_mode: 1
---

# Code Style Guide

## Table of Contents

1. [General Rules](#general-rules)
2. [Naming](#naming)
3. [Class Structure](#class-structure)
4. [Widgets](#widgets)
5. [BLoC Classes](#bloc-classes)
6. [Repositories](#repositories)
7. [Collections and Loops](#collections-and-loops)
8. [Asynchronous Programming](#asynchronous-programming)
9. [Dependencies](#dependencies)

## General Rules

### 1. Mandatory Trailing Commas

Always add trailing commas after the last parameter in multi-line function calls and constructors. This improves code readability and simplifies adding new parameters.

```dart
CustomButton(
  onPressed: () => print('Pressed'),
  child: const Text('Button'),
);
```

### 2. Always use curly braces in control flow structures.

**GOOD:**

```dart
if (!context.mounted) {
  return;
}
```

**BAD:**

```dart
if (!context.mounted) return;
```

## Naming

### 1. Abstract Classes and Their Implementations

Abstract classes are written without a prefix, while classes that implement them should contain the Impl suffix or a functional description.

```dart
/// Abstract class
abstract interface class UserRepository {}

/// Main implementation (prod and stage environment)
class UserRepositoryImpl implements UserRepository {}

/// Other implementation should contain functional description:
/// - Network - network interaction
/// - Local - local storage
/// - Mock - mock repository
class UserRepositoryLocal implements UserRepository {}
```

### 2. Private Classes with "\_" Prefix

Private classes should start with an underscore. This is the standard Dart convention for denoting private elements in a library.

```dart
class _ButtonTitleExampleState extends State<ButtonTitleExample> {}
```

### 3. Private Fields and Methods with "\_" Prefix

All private fields and methods of a class should start with an underscore. This ensures encapsulation and clearly separates public and private API.

```dart
class MyClass {
  final String _apiKey = 'secret';

  void _processData() {
    /// Private method.
  }
}
```

### 4. Loop Variables - Single Letter

Use short names for loop variables (i, j, k) or prefer for-in loops with meaningful names. Avoid long names like index, counter for simple iterations.

```dart
for (int i = 0; i < items.length; i++) {
  print(items[i]);
}

/// Or even better:
for (final item in items) {
  print(item);
}
```

### 5. Comments

In TODO comments, specify the author in parentheses.
The author format should follow the pattern: "firstLetterOfName.fullLastname".

```dart
// TODO(m.semenov): Fix this logic.
class UserService {
  /// Gets user data.
  User getUser() {
    return user;
  }
}
```

## Class Structure

### 1. Order of Elements in Class

Maintain a specific order of elements in a class to improve readability and make code navigation easier:

1. **Static public and private methods and fields**
2. **Final fields (public and private) initialized in constructor**
3. **Constructors**
4. **Other private fields**
5. **Public methods**
6. **Private methods**

```dart
class UserRepository {
  /// 1. Static public constants
  static const String baseUrl = 'https://api.example.com';

  /// 1. Static private constants
  static const String _defaultTimeout = '30s';

  /// 1. Static public methods
  static String formatUrl(String endpoint) => '$baseUrl/$endpoint';

  /// 1. Static private methods
  static bool _isValidUrl(String url) => url.startsWith('http');

  /// 2. Final fields initialized in constructor (public)
  final String userId;

  /// 2. Final fields initialized in constructor (private)
  final ApiClient _apiClient;
  final Logger _logger;

  /// 3. Constructor
  UserRepository({
    required this.userId,
    required ApiClient apiClient,
    required Logger logger,
  }) : _apiClient = apiClient,
       _logger = logger;

  /// 4. Other private fields
  String? _cachedUserName;
  bool _isInitialized = false;

  /// 5. Public methods
  Future<User> getUser() async {
    return _fetchUser();
  }

  void saveUser(User user) {
    _validateUser(user);
  }

  /// 6. Private methods
  Future<User> _fetchUser() async {
    /// Implementation
    return User();
  }

  void _validateUser(User user) {
    /// Validation logic
  }
}
```

## Widgets

### 1. Lifecycle Methods Order

Maintain a specific order for lifecycle methods in StatefulWidget:

1. **initState** - always first
2. **didUpdateWidget, didChangeDependencies** - in any order after initState
3. **build** - main widget method
4. **dispose** - always last

```dart
class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(MyWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
```

### 2. Custom Methods After Lifecycle Methods

Place methods that are not inherited from State after all lifecycle methods (after dispose). This maintains clear separation between Flutter's lifecycle methods and custom widget logic.

```dart
class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Container(),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleTap() {}

  void _validateInput(String input) {}
}
```

### 3. Using Arrow Functions

Use arrow functions for simple one-line methods, especially in build() methods. This makes code more compact and readable.

```dart
class SimpleWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Text('Simple text');
}
```

### 4. Private Fields in StatefulWidget State

Always make fields in State classes private, except in rare cases when you need to access the state through GlobalKey and call its methods.

**GOOD:**

```dart
class _MyWidgetState extends State<MyWidget> {
  String _userName = '';  /// Private field
  bool _isLoading = false;  /// Private field

  @override
  Widget build(BuildContext context) {
    return Text(_userName);
  }
}
```

**Exception (rare case with GlobalKey):**

```dart
class _FormWidgetState extends State<FormWidget> {
  String _userName = '';  /// Private field

  /// Public method for external access via GlobalKey
  void validateAndSubmit() {
    /// Validation logic
  }

  @override
  Widget build(BuildContext context) {
    return Form(child: TextFormField());
  }
}

/// Usage with GlobalKey
final formKey = GlobalKey<_FormWidgetState>();
/// Later: formKey.currentState?.validateAndSubmit();
```

## BLoC Classes

### 1. BLoC Class Structure

Maintain a specific order of elements in BLoC classes to ensure logical structure and ease of understanding:

1. **Final fields (public and private) initialized in constructor**
2. **Constructor with handler registration**
3. **Private fields (e.g., subscriptions)**
4. **Event handlers**

```dart
class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  /// 1. Final fields initialized in constructor (public)
  final String userId;

  /// 1. Final fields initialized in constructor (private)
  final GlobalAppSettingsRepository _globalAppSettingsRepository;
  final Logger _logger;

  /// 2. Constructor with handler registration
  ThemeBloc({
    required this.userId,
    required GlobalAppSettingsRepository globalAppSettingsRepository,
    required Logger logger,
  })  : _globalAppSettingsRepository = globalAppSettingsRepository,
        _logger = logger,
        super(
          ThemeState(
            themeMode: globalAppSettingsRepository.settings.themeMode,
          ),
        ) {
    on<_OnChangeThemeEvent>(_onChangeThemeMode);
    on<_OnResetThemeEvent>(_onResetTheme);
  }

  /// 3. Private fields (subscriptions, etc.)
  StreamSubscription<ThemeMode>? _themeSubscription;
  Timer? _debounceTimer;

  /// 4. Event handlers
  Future<void> _onChangeThemeMode(
    _OnChangeThemeEvent event,
    Emitter<ThemeState> emit,
  ) async {
    /// Logic
  }

  Future<void> _onResetTheme(
    _OnResetThemeEvent event,
    Emitter<ThemeState> emit,
  ) async {
    /// Reset logic
  }
}
```

### 2. Naming Events as Past Actions

Name events as actions that have already occurred, not as commands. Use past tense to describe the event.

```dart
// Sounds like an event that happened
class ThemeChanged extends ThemeEvent {}
class ButtonPressed extends ButtonEvent {}
class PullRefreshTriggered extends RefreshEvent {}
class UserDataRequested extends UserEvent {}
class PageScrolled extends ScrollEvent {}
```

## Repositories

## Data Models

### 1. Using Factory Constructors for Mappers

Use factory constructors to create objects from external data (API, database). This ensures API cleanliness and ease of use.

```dart
@freezed
class AWTransaction with _$AWTransaction {
  const factory AWTransaction({
    required String id,
    required Decimal amount,
  }) = _AWTransaction;

  factory AWTransaction.fromApi(ApiTransaction apiTransaction) => AWTransaction(
    id: apiTransaction.id,
    amount: Decimal.parse(apiTransaction.amount),
  );
}
```

### 2. Using DateTime.now() Directly

Avoid direct calls to DateTime.now() in business logic. Use DateTimeRepository to ensure testability and mocking capability.

```dart
/// Use DateTimeRepository for testability.
final timestamp = dateTimeRepository.now();
```

## Collections and Loops

### 1. Using for-in Loops

Prefer for-in loops over regular for loops for iterating over collections.

```dart
for (final user in users) {
  processUser(user);
}
```

## Asynchronous Programming

### 1. Using Future

Don't wrap synchronous operations in Future unnecessarily. Use async/await only for truly asynchronous operations.

```dart
String getName() => 'John';

/// Or if you really need Future:
Future<String> getNameFromApi() async {
  final response = await apiClient.getName();
  return response.name;
}
```

## Dependencies

### 1. Using Versions Without Caret (^)

Use exact dependency versions without caret to ensure build stability and predictable behavior.

```yaml
dependencies:
  http: 0.13.0
  shared_preferences: 2.0.0
```

### 2. Ordered Dependencies

Sort dependencies alphabetically for better readability and easier search for needed dependencies. Flutter SDK dependencies should be placed first, followed by other dependencies in alphabetical order.

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  app_settings: 6.1.1
  bloc_concurrency: 0.2.5
  cupertino_icons: 1.0.2
  http: 0.13.0
  shared_preferences: 2.0.0
```
