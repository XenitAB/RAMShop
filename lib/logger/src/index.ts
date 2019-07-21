import pino from "pino";
import { NextHandleFunction } from "connect";
import expressPinoLogger from "express-pino-logger";

// "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent"

export const logger = pino({
  name: process.env.SERVICE_NAME,
  level: process.env.LOG_LEVEL
});

export const expressLogger: NextHandleFunction = expressPinoLogger({
  logger
});
