declare module "express-pino-logger" {
  import { NextHandleFunction } from "connect";
  import { Logger, LoggerOptions } from "pino";

  function expressPinoLogger(
    options: LoggerOptions | { logger: Logger }
  ): NextHandleFunction;

  export = expressPinoLogger;
}
