#!/usr/bin/env node
import { run } from "./run.js";

// A closed pipe (`misardev … | head`) is not an error worth a stack trace.
process.stdout.on("error", (err: NodeJS.ErrnoException) => {
  if (err.code === "EPIPE") process.exit(0);
  throw err;
});

run(process.argv.slice(2)).then((code) => {
  process.exitCode = code;
});
