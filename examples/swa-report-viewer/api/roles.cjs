'use strict';

// This is a claims mapper, not a token verifier. Only SWA's isolated rolesSource
// callback may supply this body. Never expose this function as a public API or
// populate it from x-ms-client-principal or other client-supplied headers.
const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TENANT = new Set(['tid', 'http://schemas.microsoft.com/identity/claims/tenantid']);
const OBJECT = new Set(['oid', 'http://schemas.microsoft.com/identity/claims/objectidentifier']);
const ROLE = new Set(['roles', 'http://schemas.microsoft.com/ws/2008/06/identity/claims/role']);
const OVERAGE = new Set(['_claim_names', '_claim_sources', 'hasgroups']);

function getRoles(body, policy) {
  const deny = { roles: [] };
  if (!policy || typeof policy.tenantId !== 'string' || !GUID.test(policy.tenantId) || policy.appRole !== 'Report.Reader' ||
      policy.siteRole !== 'report_reader') return deny;
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      body.identityProvider !== 'aad' || typeof body.userId !== 'string' ||
      body.userId.length === 0 || body.userId.length > 256 ||
      !Array.isArray(body.claims) || body.claims.length === 0 || body.claims.length > 128) return deny;
  const tenant = [], object = [], roles = [];
  for (const claim of body.claims) {
    if (!claim || typeof claim !== 'object' || Array.isArray(claim) ||
        Object.keys(claim).sort().join(',') !== 'typ,val' ||
        typeof claim.typ !== 'string' || typeof claim.val !== 'string' ||
        claim.typ.length > 256 || claim.val.length > 2048 || OVERAGE.has(claim.typ)) return deny;
    if (TENANT.has(claim.typ)) tenant.push(claim.val);
    if (OBJECT.has(claim.typ)) object.push(claim.val);
    if (ROLE.has(claim.typ)) roles.push(claim.val);
  }
  // A duplicate semantic tenant/object claim is ambiguous, even if values agree.
  if (tenant.length !== 1 || tenant[0] !== policy.tenantId ||
      object.length !== 1 || !GUID.test(object[0]) || roles.length > 32 ||
      new Set(roles).size !== roles.length || !roles.includes(policy.appRole)) return deny;
  return { roles: [policy.siteRole] };
}

module.exports = { getRoles };
