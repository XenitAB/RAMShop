import express from "express";

const app = express();
const port = process.env.PORT;

app.get("/cart/api/v1/echo", (req, res) => {
  console.log("new request");
  res.send("echo");
});

app.get("/healthz", (req, res) => {
  res.send("ok");
});

app.listen(port, () => console.log(`Cart service listening on port ${port}`));
