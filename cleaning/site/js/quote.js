/* Salty Air Home Cleaning — instant quote widget
   Mounted into any element with id="quote-mount".
   data-mode="teaser"  -> CTA links to book.html with selections in the URL
   data-mode="booking" -> CTA scrolls to the booking form; state readable via SaltyQuote.state
*/

const PRICING = {
  base: 120,            // 1 bed / 1 bath standard clean
  perBedroom: 40,
  perBathroom: 15,
  sqft: { s1: 0, s2: 15, s3: 35, s4: 65, s5: 100 },
  type: { standard: 1, deep: 1.5, move: 1.75 },
  freq: { onetime: 1, monthly: 0.9, biweekly: 0.85, weekly: 0.8 },
  addons: {
    fridge:  { label: "Inside fridge",    price: 35 },
    oven:    { label: "Inside oven",      price: 30 },
    windows: { label: "Interior windows", price: 45 },
    laundry: { label: "Laundry & fold",   price: 25 },
    garage:  { label: "Garage sweep-out", price: 40 },
    linens:  { label: "Change bed linens", price: 20 },
  },
};

const SQFT_LABELS = {
  s1: "Under 1,500 sq ft", s2: "1,500–2,500 sq ft", s3: "2,500–3,500 sq ft",
  s4: "3,500–4,500 sq ft", s5: "4,500+ sq ft",
};
const FREQ_LABELS = { weekly: "Weekly", biweekly: "Bi-weekly", monthly: "Monthly", onetime: "One-time" };
const FREQ_SAVE = { weekly: "save 20%", biweekly: "save 15%", monthly: "save 10%", onetime: "" };
const TYPE_LABELS = { standard: "Standard", deep: "Deep clean", move: "Move in/out" };

const state = {
  beds: 3, baths: 2, sqft: "s3", type: "standard", freq: "biweekly", addons: [],
};

function computePrice(s) {
  let core = PRICING.base
    + (s.beds - 1) * PRICING.perBedroom
    + (s.baths - 1) * PRICING.perBathroom
    + PRICING.sqft[s.sqft];
  core = core * PRICING.type[s.type] * PRICING.freq[s.freq];
  const addons = s.addons.reduce((sum, k) => sum + PRICING.addons[k].price, 0);
  return Math.round((core + addons) / 5) * 5;
}

function readParams() {
  const p = new URLSearchParams(location.search);
  if (p.get("beds")) state.beds = Math.min(6, Math.max(1, +p.get("beds") || 3));
  if (p.get("baths")) state.baths = Math.min(5, Math.max(1, +p.get("baths") || 2));
  if (PRICING.sqft[p.get("sqft")]) state.sqft = p.get("sqft");
  if (PRICING.type[p.get("type")]) state.type = p.get("type");
  if (PRICING.freq[p.get("freq")]) state.freq = p.get("freq");
  if (p.get("addons")) state.addons = p.get("addons").split(",").filter((k) => PRICING.addons[k]);
}

function toParams() {
  const p = new URLSearchParams({
    beds: state.beds, baths: state.baths, sqft: state.sqft,
    type: state.type, freq: state.freq,
  });
  if (state.addons.length) p.set("addons", state.addons.join(","));
  return p.toString();
}

function el(html) {
  const t = document.createElement("template");
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
}

function options(n, sel, suffix) {
  let out = "";
  for (let i = 1; i <= n; i++) {
    out += `<option value="${i}" ${i === sel ? "selected" : ""}>${i}${i === n ? "+" : ""} ${suffix}${i > 1 ? "s" : ""}</option>`;
  }
  return out;
}

function buildWidget(mount) {
  const mode = mount.dataset.mode || "teaser";
  const card = el(`
    <div class="quote-card">
      <div class="quote-card-head">
        <h3>Price your clean</h3><span>60 seconds, no phone call</span>
      </div>
      <div class="q-row">
        <div class="q-field"><label for="q-beds">Bedrooms</label>
          <select id="q-beds">${options(6, state.beds, "bedroom")}</select></div>
        <div class="q-field"><label for="q-baths">Bathrooms</label>
          <select id="q-baths">${options(5, state.baths, "bathroom")}</select></div>
      </div>
      <div class="q-row">
        <div class="q-field"><label for="q-sqft">Home size</label>
          <select id="q-sqft">${Object.keys(SQFT_LABELS).map((k) =>
            `<option value="${k}" ${k === state.sqft ? "selected" : ""}>${SQFT_LABELS[k]}</option>`).join("")}</select></div>
        <div class="q-field"><label>Clean type</label>
          <div class="seg" id="q-type">${Object.keys(TYPE_LABELS).map((k) =>
            `<button type="button" data-k="${k}" class="${k === state.type ? "on" : ""}">${TYPE_LABELS[k]}</button>`).join("")}</div></div>
      </div>
      <div class="q-field" style="margin-bottom:14px"><label>How often?</label>
        <div class="pills" id="q-freq">${Object.keys(FREQ_LABELS).map((k) =>
          `<button type="button" data-k="${k}" class="${k === state.freq ? "on" : ""}">${FREQ_LABELS[k]}${
            FREQ_SAVE[k] ? `<small>${FREQ_SAVE[k]}</small>` : ""}</button>`).join("")}</div></div>
      <div class="q-field"><label>Add-ons</label>
        <div class="addons" id="q-addons">${Object.keys(PRICING.addons).map((k) =>
          `<label class="addon"><input type="checkbox" value="${k}" ${state.addons.includes(k) ? "checked" : ""}>
           ${PRICING.addons[k].label} <span><b>+$${PRICING.addons[k].price}</b></span></label>`).join("")}</div></div>
      <div class="q-price">
        <div>
          <div class="q-price-label">Your price</div>
          <div class="q-price-note" id="q-note"></div>
        </div>
        <div class="q-price-num" id="q-num"></div>
      </div>
      ${mode === "teaser"
        ? `<a class="btn btn-primary q-cta" id="q-cta" href="book.html">Book this clean &rarr;</a>`
        : `<a class="btn btn-primary q-cta" href="#book-form">Looks right &mdash; request this clean &darr;</a>`}
      <p class="q-fine">First visit is priced as a deep clean so your recurring rate stays low. No contracts &middot; cancel anytime.</p>
    </div>`);
  mount.appendChild(card);

  card.querySelector("#q-beds").addEventListener("change", (e) => update({ beds: +e.target.value }));
  card.querySelector("#q-baths").addEventListener("change", (e) => update({ baths: +e.target.value }));
  card.querySelector("#q-sqft").addEventListener("change", (e) => update({ sqft: e.target.value }));
  card.querySelector("#q-type").addEventListener("click", (e) => {
    const b = e.target.closest("button"); if (!b) return;
    card.querySelectorAll("#q-type button").forEach((x) => x.classList.toggle("on", x === b));
    update({ type: b.dataset.k });
  });
  card.querySelector("#q-freq").addEventListener("click", (e) => {
    const b = e.target.closest("button"); if (!b) return;
    card.querySelectorAll("#q-freq button").forEach((x) => x.classList.toggle("on", x === b));
    update({ freq: b.dataset.k });
  });
  card.querySelector("#q-addons").addEventListener("change", () => {
    state.addons = [...card.querySelectorAll("#q-addons input:checked")].map((i) => i.value);
    update({});
  });

  function update(patch) {
    Object.assign(state, patch);
    render();
    document.dispatchEvent(new CustomEvent("quote:change"));
  }

  function render() {
    const num = card.querySelector("#q-num");
    const price = computePrice(state);
    num.innerHTML = `<sup>$</sup>${price}${state.freq !== "onetime" ? "<small>/visit</small>" : ""}`;
    num.classList.remove("tick");
    void num.offsetWidth;
    num.classList.add("tick");
    card.querySelector("#q-note").textContent =
      state.freq === "onetime" ? "One-time visit" : `${FREQ_LABELS[state.freq]} · ${FREQ_SAVE[state.freq]}`;
    const cta = card.querySelector("#q-cta");
    if (cta) cta.href = `book.html?${toParams()}`;
  }

  render();
}

readParams();
document.querySelectorAll("#quote-mount, [data-quote-mount]").forEach(buildWidget);

window.SaltyQuote = {
  state,
  price: () => computePrice(state),
  summary: () => [
    `${state.beds} bed / ${state.baths} bath, ${SQFT_LABELS[state.sqft]}`,
    `${TYPE_LABELS[state.type]} · ${FREQ_LABELS[state.freq]}`,
    state.addons.length ? "Add-ons: " + state.addons.map((k) => PRICING.addons[k].label).join(", ") : "No add-ons",
    `Quoted price: $${computePrice(state)}${state.freq !== "onetime" ? "/visit" : ""}`,
  ].join("\n"),
};
