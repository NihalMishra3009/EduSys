class ApiConfigDev {
  static const String baseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "http://10.222.20.32:8000",
  );
}
