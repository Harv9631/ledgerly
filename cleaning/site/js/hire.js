/* Salty Air — cleaning team application form.
   Opens a pre-filled email to the hiring inbox; no backend needed. */

const HIRE_EMAIL = "info@saltyairhomecleaning.com";

const form = document.getElementById("hire-form");
const errorEl = document.getElementById("h-error");

form.addEventListener("submit", (e) => {
  e.preventDefault();
  errorEl.classList.remove("show");

  const data = Object.fromEntries(new FormData(form).entries());
  const required = ["name", "phone", "email", "area", "experience"];
  if (required.some((k) => !data[k] || !data[k].trim())) {
    errorEl.classList.add("show");
    return;
  }

  const body = encodeURIComponent(
    `New cleaning team application\n\nName: ${data.name}\nPhone: ${data.phone}\nEmail: ${data.email}\nService area: ${data.area}\nTeam size: ${data.team_size}\n\nExperience:\n${data.experience}`
  );
  location.href = `mailto:${HIRE_EMAIL}?subject=${encodeURIComponent("Team application — " + data.name)}&body=${body}`;

  form.innerHTML = `
    <div class="form-success">
      <svg width="72" height="72" viewBox="0 0 72 72" aria-hidden="true">
        <circle cx="36" cy="36" r="34" fill="#DCEAE4"/>
        <path d="M22 37l9 9 19-19" stroke="#4E8B7C" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </svg>
      <h3>Application sent!</h3>
      <p>Your email app should have opened with your application ready to send. We reply to every applicant within two business days.</p>
    </div>`;
});
