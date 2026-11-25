/* A renderer for the evaluator's public 1.0 contract. It never calculates money. */
function renderCostPilot(result) {
  if (result?.schemaVersion !== "1.0" || !Array.isArray(result.profiles)) {
    throw new Error("Select a version 1.0 cost estimate.");
  }
  const escape = (value) => String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
  const { currency, region, periodStart, asOf, users, devices } = result.request;
  const trio = (amounts) => ["low", "base", "high"].map((scenario) => (
    `<td>${amounts ? escape(amounts[scenario]) : "—"}</td>`
  )).join("");
  const categories = [
    ["fixed", "Monthly baseline"],
    ["usage", "Usage"],
    ["oneTime", "One-time"],
    ["optional", "Optional"],
    ["knownTotal", "Known total"],
  ];
  const table = (caption, rows) => `<table><caption>${caption}</caption><thead><tr>
    <th scope="col">Item</th><th scope="col">Low</th><th scope="col">Base</th><th scope="col">High</th>
    </tr></thead><tbody>${rows}</tbody></table>`;
  const totals = (caption, amounts) => table(caption, categories.map(([key, label]) =>
    `<tr><th scope="row">${label}</th>${trio(amounts[key])}</tr>`).join(""));
  const textRows = result.profiles.map((profile) => {
    const lines = profile.lines.map((line) => {
      const evidence = line.observation
        ? ` · price observed ${escape(line.observation.observedOn)}`
        : "";
      const measured = line.measurement
        ? `<small>Measured ${escape(line.measurement.coverage)} usage: ${escape(line.measurement.quantity)} ${escape(line.measurement.unit)}</small>`
        : "";
      const allocation = line.allocatedElsewhere ? " · allocated to another profile" : "";
      const label = `${escape(line.label)} · ${escape(line.status)}${evidence}${allocation}<small>${escape(line.reason)}</small>${measured}`;
      return `<tr><th scope="row">${label}</th>${trio(line.incremental)}</tr>`;
    }).join("");
    const options = Object.entries(profile.options)
      .map(([name, value]) => `${escape(name)}=${escape(value)}`)
      .join(", ");
    return `<section><h2>${escape(profile.id)} · ${escape(profile.configuration)}</h2>
      <p>${options}</p><p>${escape(profile.runs)} scheduled runs · ${escape(profile.retentionDays)} retention days</p>
      ${lines ? table("Line estimates after shared allocation", lines) : ""}
      ${totals("Standalone estimate", profile.standalone)}
      ${totals("Incremental estimate", profile.incremental)}
      ${profile.exclusions.length ? `<h3>Excluded charges</h3><ul>${
        profile.exclusions.map((item) => `<li>${escape(item)}</li>`).join("")
      }</ul>` : ""}</section>`;
  }).join("");
  return `<p>${escape(periodStart)} · ${escape(region)} · ${escape(currency)} · evaluated ${escape(asOf)}</p>
    <p>${escape(users)} users · ${escape(devices)} devices · synthetic price fixture</p>
    ${result.complete ? "" : '<p role="status">Partial estimate. Some prices are unavailable or stale.</p>'}
    ${totals("Portfolio incremental estimate", result.portfolio)}
    ${result.unallocated.length ? `<h2>Unallocated shared costs</h2><ul>${
      result.unallocated.map(({ profile, label }) => `<li>${escape(profile)} · ${escape(label)}</li>`).join("")
    }</ul>` : ""}${textRows}`;
}

if (typeof module === "object" && module.exports) module.exports = { renderCostPilot };
