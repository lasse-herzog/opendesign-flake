// Use upstream's packaged runtime with this immutable Nix resource tree.
const { app } = require("electron");
app.setName("Open Design");
import("./apps/packaged/dist/index.mjs").catch((error) => {
  console.error("Open Design could not start", error);
  app.exit(1);
});
