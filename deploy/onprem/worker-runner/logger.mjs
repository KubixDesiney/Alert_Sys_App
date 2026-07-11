// Structured JSON-line logger for the on-prem services. One line per event so
// `docker logs`, journald and log shippers can all parse it.
export function makeLogger(service, sink = console) {
  const emit = (level, msg, fields = {}) => {
    const line = JSON.stringify({
      ts: new Date().toISOString(),
      level,
      service,
      msg,
      ...fields,
    });
    if (level === 'error') sink.error(line);
    else if (level === 'warn') sink.warn(line);
    else sink.log(line);
  };
  return {
    info: (msg, fields) => emit('info', msg, fields),
    warn: (msg, fields) => emit('warn', msg, fields),
    error: (msg, fields) => emit('error', msg, fields),
  };
}
