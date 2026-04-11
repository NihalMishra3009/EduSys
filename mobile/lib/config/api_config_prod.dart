class ApiConfigProd {
  static const String baseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://edusys-production-9800.up.railway.app",
  );
}

