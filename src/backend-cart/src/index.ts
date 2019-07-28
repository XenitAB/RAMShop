import express from "express";
import { expressLogger } from "@ramshop/logger";

const app = express();
const port = process.env.PORT;

app.get("/healthz", (req, res) => {
  res.send("ok");
});

app.use(expressLogger);

app.get("/api/v1/cart/:id", (req, res) => {
  res.json({ id: req.params.id }).send();
});

app.listen(port, () => console.log(`Cart service listening on port ${port}`));
