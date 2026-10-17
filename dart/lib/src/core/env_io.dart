import 'dart:io' show Platform;

/// Read [name] from the process environment.
String? readEnvironment(String name) => Platform.environment[name];
