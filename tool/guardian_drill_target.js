// Guardian drill target — a REAL, CI-checked module that the drill deliberately
// breaks (by removing a bracket) and the joint Fix+Review AI then repairs.
//
// It is intentionally small and side-effect free so that, even though the drill
// commits a genuinely broken version to the branch under test, nothing in the
// running product depends on it. `node --check` (and the drill's --verify step)
// validate it, so a broken state shows up as a real red check.

export function severityRank(level) {
  switch (String(level || '').toLowerCase()) {
    case 'critical':
      return 3;
    case 'warning':
      return 2;
    case 'normal':
      return 1;
    default:
      return 0;
  }
}

export function isActionable(level) {
  return severityRank(level) >= 2;
}

// Simple self-check so the file is meaningful on its own.
export function _selfTest() {
  return severityRank('critical') === 3 && isActionable('warning') === true && isActionable('normal') === false;
}
