class ApiConfigProd {
  static const String baseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://api.example.com",
  );
}

