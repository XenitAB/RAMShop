import express from "express";
import { expressLogger } from "@ramshop/logger";

const app = express();
const port = process.env.PORT;

app.get("/healthz", (req, res) => {
  res.send("ok");
});

app.use(expressLogger);

app.get("/cart/api/v1/echo", (req, res) => {
  res.send("echo");
});

app.listen(port, () => console.log(`Cart service listening on port ${port}`));
