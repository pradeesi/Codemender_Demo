/**
 * Purpose: Client-side interactive scripting for ApexFin Banking Portal.
 * Architecture/Context: Front-end event handlers for form interactions and status feedback.
 * Dependencies/Side Effects: Interacts with DOM input fields and Bootstrap alert elements.
 */

document.addEventListener("DOMContentLoaded", () => {
    // Auto-dismiss alerts after 5 seconds
    const alerts = document.querySelectorAll(".alert-dismissible");
    alerts.forEach((alert) => {
        setTimeout(() => {
            try {
                const bsAlert = bootstrap.Alert.getOrCreateInstance(alert);
                if (bsAlert) {
                    bsAlert.close();
                }
            } catch (e) {
                // Ignore if alert already dismissed
            }
        }, 5000);
    });

    // Provide visual feedback during diagnostic probe execution
    const diagForm = document.getElementById("diagnosticsForm");
    const runBtn = document.getElementById("runDiagnosticBtn");
    if (diagForm && runBtn) {
        diagForm.addEventListener("submit", () => {
            runBtn.disabled = true;
            runBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status"></span>Pinging Gateway...';
        });
    }

    // Enhance search input usability and auto-select existing content on focus
    const searchInput = document.getElementById("searchInput");
    if (searchInput) {
        searchInput.addEventListener("focus", function() {
            if (this.value) {
                this.select();
            }
        });
    }
});
