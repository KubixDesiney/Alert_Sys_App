// Mini-evaluator for the subset of PocketBase API-rule syntax used in
// pb_schema.json. Test infrastructure ONLY: it lets worker_test/onprem_rbac
// exercise the real rule strings against an authorization matrix without a
// live PocketBase. Supported: string/number/bool literals, && || ( ),
// = != > < >= <=, @request.auth.X, @request.data.X, @request.data.X:isset,
// @now, and bare record field names.
//
// Semantics mirrored from PocketBase:
//  * rule === null  -> locked (only superusers / service token) => false here
//  * rule === ""    -> public => true
//  * missing fields read as "" (so `disabled != true` passes when unset)
//  * dates are compared as ISO-8601 UTC strings (lexicographic == temporal)

const TOKEN_RE =
  /\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|@request\.auth\.[A-Za-z_][\w]*|@request\.data\.[A-Za-z_][\w]*(?::isset)?|@now|&&|\|\||!=|>=|<=|=|>|<|\(|\)|true|false|null|-?\d+(?:\.\d+)?|[A-Za-z_][\w]*)/y;

export function tokenize(rule) {
  const out = [];
  let i = 0;
  while (i < rule.length) {
    TOKEN_RE.lastIndex = i;
    const m = TOKEN_RE.exec(rule);
    if (!m) {
      if (rule.slice(i).trim() === '') break;
      throw new Error(`rules_eval: cannot tokenize at "${rule.slice(i, i + 20)}"`);
    }
    out.push(m[1]);
    i = TOKEN_RE.lastIndex;
  }
  return out;
}

function transpile(rule) {
  const js = tokenize(rule).map((t) => {
    if (t.startsWith('"') || t.startsWith("'")) return t;
    if (t === '&&' || t === '||' || t === '(' || t === ')') return t;
    if (t === '=') return '===';
    if (t === '!=') return '!==';
    if (t === '>' || t === '<' || t === '>=' || t === '<=') return t;
    if (t === 'true' || t === 'false' || t === 'null') return t;
    if (/^-?\d/.test(t)) return t;
    if (t === '@now') return 'ctx.now';
    if (t.startsWith('@request.auth.')) {
      const f = t.slice('@request.auth.'.length);
      return `(ctx.auth["${f}"] ?? "")`;
    }
    if (t.startsWith('@request.data.')) {
      const rest = t.slice('@request.data.'.length);
      if (rest.endsWith(':isset')) {
        const f = rest.slice(0, -':isset'.length);
        return `(Object.prototype.hasOwnProperty.call(ctx.data,"${f}"))`;
      }
      return `(ctx.data["${rest}"] ?? "")`;
    }
    // bare identifier -> record field
    return `(ctx.record["${t}"] ?? "")`;
  });
  return js.join(' ');
}

/**
 * Evaluate a PocketBase rule string.
 * @param {string|null} rule
 * @param {{auth?:object, record?:object, data?:object, now?:string}} ctx
 */
export function evalRule(rule, ctx = {}) {
  if (rule === null || rule === undefined) return false; // locked
  if (String(rule).trim() === '') return true; // public
  const full = {
    auth: ctx.auth || {},
    record: ctx.record || {},
    data: ctx.data || {},
    now: ctx.now || new Date().toISOString(),
  };
  // eslint-disable-next-line no-new-func
  const fn = new Function('ctx', `return !!(${transpile(String(rule))});`);
  return fn(full);
}

/** Convenience: evaluate one operation on a collection def from pb_schema.json. */
export function can(collection, op, ctx) {
  const rule = collection[`${op}Rule`];
  return evalRule(rule, ctx);
}
