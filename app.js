const chatLauncher = document.querySelector("#chat-launcher");
const chatPanel = document.querySelector("#chat-panel");
const chatClose = document.querySelector("#chat-close");
const chatForm = document.querySelector("#chat-form");
const chatInput = document.querySelector("#chat-input");
const chatMessages = document.querySelector("#chat-messages");
const chatSuggestions = document.querySelector("#chat-suggestions");
const modelStatus = document.querySelector("#model-status");
const modelStatusDot = document.querySelector("#model-status-dot");
const chatHistory = [];
let waitingForReply = false;

function setChatOpen(open) {
  chatPanel.classList.toggle("is-open", open);
  chatPanel.setAttribute("aria-hidden", String(!open));
  chatLauncher.setAttribute("aria-expanded", String(open));
  if (open) chatInput.focus();
}

function addMessage(role, content, isError = false) {
  const row = document.createElement("div");
  row.className = `message-row ${role === "user" ? "user-row" : "assistant-row"}`;
  if (role !== "user") {
    const avatar = document.createElement("div");
    avatar.className = "message-avatar";
    avatar.textContent = "✳";
    row.append(avatar);
  }
  const bubble = document.createElement("div");
  bubble.className = `message ${role === "user" ? "user-message" : "assistant-message"}${isError ? " message-error" : ""}`;
  bubble.textContent = content;
  row.append(bubble);
  chatMessages.append(row);
  chatMessages.scrollTop = chatMessages.scrollHeight;
  return row;
}

function addTypingIndicator() {
  const row = document.createElement("div");
  row.className = "message-row assistant-row";
  const avatar = document.createElement("div");
  avatar.className = "message-avatar";
  avatar.textContent = "✳";
  const indicator = document.createElement("div");
  indicator.className = "message assistant-message typing-indicator";
  indicator.setAttribute("aria-label", "Nova is thinking");
  indicator.innerHTML = "<span></span><span></span><span></span>";
  row.append(avatar, indicator);
  chatMessages.append(row);
  chatMessages.scrollTop = chatMessages.scrollHeight;
  return row;
}

async function sendMessage(text) {
  const prompt = text.trim();
  if (!prompt || waitingForReply) return;

  waitingForReply = true;
  chatInput.value = "";
  chatForm.querySelector("button").disabled = true;
  chatSuggestions.hidden = true;
  addMessage("user", prompt);
  chatHistory.push({ role: "user", content: prompt });
  const typing = addTypingIndicator();

  try {
    const response = await fetch("/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ messages: chatHistory.slice(-20) }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || `Chat request failed (${response.status}).`);
    typing.remove();
    addMessage("assistant", result.reply);
    chatHistory.push({ role: "assistant", content: result.reply });
  } catch (error) {
    typing.remove();
    addMessage("assistant", `I couldn't get a reply just now. ${error.message}`, true);
    chatHistory.pop();
  } finally {
    waitingForReply = false;
    chatForm.querySelector("button").disabled = false;
    chatInput.focus();
  }
}

async function checkModelStatus() {
  try {
    const response = await fetch("/api/health");
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "Could not check the model.");
    if (!result.ollama) {
      modelStatus.textContent = "Ollama is offline";
      modelStatusDot.className = "status-dot offline";
    } else if (!result.modelAvailable) {
      modelStatus.textContent = `${result.model} not found`;
      modelStatusDot.className = "status-dot offline";
    } else {
      modelStatus.textContent = `${result.model} · ready`;
      modelStatusDot.className = "status-dot online";
    }
  } catch (error) {
    modelStatus.textContent = "Could not check Ollama";
    modelStatusDot.className = "status-dot offline";
    console.error("Model health check failed:", error);
  }
}

chatLauncher.addEventListener("click", () => setChatOpen(chatPanel.getAttribute("aria-hidden") === "true"));
chatClose.addEventListener("click", () => setChatOpen(false));
chatForm.addEventListener("submit", (event) => {
  event.preventDefault();
  sendMessage(chatInput.value);
});
chatSuggestions.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-prompt]");
  if (button) sendMessage(button.dataset.prompt);
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && chatPanel.classList.contains("is-open")) {
    setChatOpen(false);
    chatLauncher.focus();
  }
});

const menuToggle = document.querySelector("#menu-toggle");
const mainNav = document.querySelector("#main-nav");
menuToggle.addEventListener("click", () => {
  const expanded = menuToggle.getAttribute("aria-expanded") === "true";
  menuToggle.setAttribute("aria-expanded", String(!expanded));
  mainNav.classList.toggle("is-open", !expanded);
});
mainNav.addEventListener("click", (event) => {
  if (event.target.closest("a")) {
    menuToggle.setAttribute("aria-expanded", "false");
    mainNav.classList.remove("is-open");
  }
});

const applicationForm = document.querySelector("#application-form");
const formStatus = document.querySelector("#form-status");
const savedApplication = localStorage.getItem("northstar-interest");
if (savedApplication) {
  const application = JSON.parse(savedApplication);
  applicationForm.elements.name.value = application.name || "";
  applicationForm.elements.email.value = application.email || "";
  applicationForm.elements.program.value = application.program || "";
  formStatus.textContent = "Your interest is saved on this device. You can update it any time.";
}

applicationForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const application = Object.fromEntries(new FormData(applicationForm));
  localStorage.setItem("northstar-interest", JSON.stringify(application));
  formStatus.textContent = `Thanks, ${application.name}! Your interest is saved on this device. This demo does not submit an application to a school.`;
});

checkModelStatus();
