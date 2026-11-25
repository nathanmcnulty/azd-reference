const { readFileSync } = require("node:fs");
const assert = require("node:assert/strict");
const { renderCostPilot } = require("./cost-view.js");

const result = JSON.parse(readFileSync(0, "utf8"));
const html = renderCostPilot(result);
const row = (label, { low, base, high }) =>
  `<th scope="row">${label}</th><td>${low}</td><td>${base}</td><td>${high}</td>`;
assert.ok(html.includes(row("Known total", result.portfolio.knownTotal)));
assert.ok(html.includes("Sentinel analytics · priced"));
assert.ok(html.includes("Unallocated shared costs"));
assert.ok(html.includes(result.unallocated[0].label));
for (const profile of result.profiles) {
  const start = html.indexOf(`<h2>${profile.id}`);
  const end = html.indexOf("</section>", start);
  assert.ok(start >= 0 && end > start);
  const section = html.slice(start, end);
  assert.ok(section.includes(row("Known total", profile.standalone.knownTotal)));
  assert.ok(section.includes(row("Known total", profile.incremental.knownTotal)));
}
result.profiles[0].lines[0].reason = "<img src=x onerror=alert(1)>";
result.complete = false;
const missing = result.profiles[2].lines.find((line) => line.id === "analytics");
missing.status = "missing";
missing.incremental = null;
const escaped = renderCostPilot(result);
assert.ok(escaped.includes("Partial estimate"));
assert.ok(escaped.includes("Sentinel analytics · missing"));
assert.ok(escaped.includes("&lt;img"));
assert.ok(!escaped.includes("<img"));
