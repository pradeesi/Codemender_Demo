/**
 * Purpose: Client-side interactive scripting for ApexFin Banking Portal.
 * Architecture/Context: Front-end event handlers for 1-click exploit payloads and copy utilities.
 * Dependencies/Side Effects: Interacts with DOM input fields and navigator.clipboard.
 */

document.addEventListener("DOMContentLoaded", () => {
    // 1-Click Exploit autofill buttons on Accounts page
    const searchInput = document.getElementById("searchInput");
    const searchForm = document.getElementById("searchForm");
    document.querySelectorAll(".exploit-btn").forEach((button) => {
        button.addEventListener("click", () => {
            const payload = button.getAttribute("data-payload");
            if (searchInput && searchForm) {
                searchInput.value = payload;
                searchForm.submit();
            }
        });
    });

    // 1-Click Exploit autofill buttons on Diagnostics page
    const hostInput = document.getElementById("hostInput");
    const diagForm = document.getElementById("diagnosticsForm");
    document.querySelectorAll(".diag-exploit-btn").forEach((button) => {
        button.addEventListener("click", () => {
            const payload = button.getAttribute("data-payload");
            if (hostInput && diagForm) {
                hostInput.value = payload;
                diagForm.submit();
            }
        });
    });

    // Clipboard copy helper for Exploit Cheat Sheet Modal
    document.querySelectorAll(".copy-btn").forEach((btn) => {
        btn.addEventListener("click", async () => {
            const textToCopy = btn.getAttribute("data-text");
            try {
                await navigator.clipboard.writeText(textToCopy);
                const originalText = btn.textContent;
                btn.textContent = "Copied!";
                btn.classList.remove("btn-outline-secondary");
                btn.classList.add("btn-success");
                setTimeout(() => {
                    btn.textContent = originalText;
                    btn.classList.remove("btn-success");
                    btn.classList.add("btn-outline-secondary");
                }, 1500);
            } catch (err) {
                console.error("Failed to copy payload to clipboard", err);
            }
        });
    });
});
