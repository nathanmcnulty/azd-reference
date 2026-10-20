'use strict';
const { getRoles } = require('../roles.cjs');
const policy = require('../policy.json');

// No body/header/token logging and no outbound clients. The platform, not this
// adapter, establishes callback provenance. Native isolation is a release gate.
module.exports = async function (context, request) {
  const result = request && request.method === 'POST' ? getRoles(request.body, policy) : { roles: [] };
  context.res = {
    status: 200,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    body: result,
  };
};
