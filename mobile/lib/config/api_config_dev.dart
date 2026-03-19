class ApiConfigDev {
  static const String baseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://edusys-production-ed0b.up.railway.app",
  );
}
