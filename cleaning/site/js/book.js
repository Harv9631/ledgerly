/* Salty Air Home Cleaning — booking request form
   FORM_ENDPOINT: set this to your Formspree (or similar) endpoint, e.g.
   "https://formspree.io/f/XXXXXXXX". Until it's set, submissions open a
   pre-filled email instead, so leads still reach you from day one. */

const FORM_ENDPOINT = ""; // TODO: paste Formspree endpoint here
const LEADS_EMAIL = "hello@saltyairhomecleaning.com"; // TODO: confirm real inbox

const form = document.getElementById("book-form");
const errorEl = document.getElementById("b-error");

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  errorEl.classList.remove("show");

  const data = Object.fromEntries(new FormData(form).entries());
  const required = ["name", "phone", "email", "address", "preferred_date"];
  if (required.some((k) => !data[k] || !data[k].trim())) {
    errorEl.classList.add("show");
    return;
  }

  data.quote = window.SaltyQuote.summary();
  const submitBtn = document.getElementById("b-submit");

  if (FORM_ENDPOINT) {
    submitBtn.disabled = true;
    submitBtn.textContent = "Sending…";
    try {
      const res = await fetch(FORM_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(data),
      });
      if (!res.ok) throw new Error("submit failed");
      showSuccess();
    } catch {
      submitBtn.disabled = false;
      submitBtn.textContent = "Request my clean";
      errorEl.textContent = "Something went wrong sending your request — please try again or email us directly.";
      errorEl.classList.add("show");
    }
  } else {
    // No endpoint configured yet: fall back to a pre-filled email
    const body = encodeURIComponent(
      `New cleaning request\n\n${data.quote}\n\nName: ${data.name}\nPhone: ${data.phone}\nEmail: ${data.email}\nAddress: ${data.address}\nFirst date: ${data.preferred_date} (${data.preferred_time})\nNotes: ${data.notes || "—"}`
    );
    location.href = `mailto:${LEADS_EMAIL}?subject=${encodeURIComponent("Cleaning request — " + data.name)}&body=${body}`;
    showSuccess();
  }
});

function showSuccess() {
  form.innerHTML = `
    <div class="form-success">
      <svg width="72" height="72" viewBox="0 0 72 72" aria-hidden="true">
        <circle cx="36" cy="36" r="34" fill="#DCEAE4"/>
        <path d="M22 37l9 9 19-19" stroke="#4E8B7C" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </svg>
      <h3>Request received!</h3>
      <p>We'll confirm your team and time within one business day. Keep an eye on your phone &mdash; welcome to Salty Air.</p>
    </div>`;
}
