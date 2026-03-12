class SessionGuard {
  static bool _isRedirecting = false;

  static bool beginRedirect() {
    if (_isRedirecting) {
      return false;
    }
    _isRedirecting = true;
    return true;
  }

  static void endRedirect() {
    _isRedirecting = false;
  }
}

