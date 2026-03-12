import "package:edusys_mobile/config/api_config_dev.dart";
import "package:edusys_mobile/config/api_config_prod.dart";

class ApiConfig {
  static const String _env = String.fromEnvironment("APP_ENV", defaultValue: "dev");
  static const String baseUrl = _env == "prod" ? ApiConfigProd.baseUrl : ApiConfigDev.baseUrl;
  static const String googleWebClientId = String.fromEnvironment(
    "GOOGLE_WEB_CLIENT_ID",
    defaultValue: "",
  );
}
