// Connects the ports of CircleDrawer to the native <dialog> API.
function connectPorts(app) {
  app.ports.setDialogOpen.subscribe(({ id, open }) => {
    if (open) {
      // Wait for Elm to render the dialog's content first, so that showModal
      // focuses it.
      requestAnimationFrame(() => {
        const dialog = document.getElementById(id);
        if (dialog && !dialog.open) dialog.showModal();
      });
    } else {
      const dialog = document.getElementById(id);
      if (dialog && dialog.open) dialog.close();
    }
  });
}
