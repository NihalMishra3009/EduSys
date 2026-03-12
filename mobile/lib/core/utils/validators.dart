class Validators {
  static String? requiredField(String? value, {String label = "Field"}) {
    if (value == null || value.trim().isEmpty) {
      return "$label is required";
    }
    return null;
  }
}
