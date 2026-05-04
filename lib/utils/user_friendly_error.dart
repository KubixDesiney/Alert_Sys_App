class UserFriendlyError {
  const UserFriendlyError._();

  static String message(Object error) {
    final text = error.toString();
    final normalized = text.toLowerCase();

    if (normalized.contains('timeout')) {
      return 'The request took too long. Please try again.';
    }
    if (normalized.contains('network') ||
        normalized.contains('socket') ||
        normalized.contains('connection')) {
      return 'Network connection issue. Please check your internet and try again.';
    }
    if (normalized.contains('permission') ||
        normalized.contains('denied') ||
        normalized.contains('unauthorized')) {
      return 'You do not have permission to complete this action.';
    }
    if (normalized.contains('not found')) {
      return 'The requested data could not be found.';
    }
    if (normalized.contains('invalid')) {
      return 'Some information is invalid. Please review it and try again.';
    }
    if (normalized.contains('firebase')) {
      return 'A server error occurred. Please try again in a moment.';
    }

    return 'Something went wrong. Please try again.';
  }
}
