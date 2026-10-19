      document.querySelectorAll(".copy").forEach(function (btn) {
        // Captured once, not per click: reading it inside the handler would capture
        // the feedback text on a second click and never restore the label.
        var label = btn.textContent;
        btn.addEventListener("click", function () {
          var flash = function (text, cls) {
            btn.textContent = text;
            btn.classList.add(cls);
            setTimeout(function () {
              btn.textContent = label;
              btn.classList.remove(cls);
            }, 1400);
          };
          var ok = function () {
            flash("copied", "done");
          };
          // writeText rejects when the clipboard permission is denied or the document
          // isn't focused, which the presence of navigator.clipboard does not rule out.
          var no = function () {
            flash("press ⌘C", "failed");
          };
          if (navigator.clipboard)
            navigator.clipboard.writeText(btn.dataset.copy).then(ok).catch(no);
          else no();
        });
      });
