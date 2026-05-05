String formatAlertClaimError(Object error) {
  final message = error.toString().toLowerCase();

  if (message.contains('already have an alert in progress') ||
      message.contains('already have a claimed alert')) {
    return 'You already have a claimed alert. Resolve it before claiming another one.';
  }

  if (message.contains('already claimed by someone else')) {
    return 'This alert was claimed by someone else before you could claim it.';
  }

  if (message.contains('this alert was already claimed')) {
    return 'This alert was claimed by someone else before you could claim it.';
  }

  return 'Claim failed: ${error.toString()}';
}