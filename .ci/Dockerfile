FROM node:lts as builder
ARG SERVICE_TYPE
ARG SERVICE
ARG PACKAGE_SCOPE
WORKDIR /usr/src/app

COPY package.json yarn.lock tsconfig.json ./
COPY lib ./lib
COPY typings ./typings

RUN yarn install
RUN yarn workspaces run build
RUN yarn workspaces run test

COPY src/${SERVICE_TYPE}-${SERVICE}/package.json ./src/${SERVICE_TYPE}-${SERVICE}/
RUN yarn install

COPY src/${SERVICE_TYPE}-${SERVICE} ./src/${SERVICE_TYPE}-${SERVICE}

RUN yarn workspace @${PACKAGE_SCOPE}/${SERVICE} build

RUN yarn workspace @${PACKAGE_SCOPE}/${SERVICE} run test

FROM node:lts-alpine
ARG SERVICE_TYPE
ARG SERVICE
WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/src/${SERVICE_TYPE}-${SERVICE}/dist/lib.node.js ./index.js

CMD ["node", "index.js"]
