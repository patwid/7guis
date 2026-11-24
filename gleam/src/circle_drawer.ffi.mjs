export function set_dialog_open(id, open) {
  if (open) {
    // Wait for Lustre to render the dialog's content first, so that showModal
    // focuses it.
    requestAnimationFrame(() => {
      const dialog = document.getElementById(id);
      if (dialog && !dialog.open) dialog.showModal();
    });
  } else {
    const dialog = document.getElementById(id);
    if (dialog && dialog.open) dialog.close();
  }
}
