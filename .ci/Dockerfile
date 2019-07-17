FROM node:lts as builder
ARG SERVICE_TYPE
ARG SERVICE
WORKDIR /usr/src/app

COPY package.json yarn.lock ./
COPY lib ./lib

RUN yarn install
RUN yarn workspaces run build
RUN yarn workspaces run test

COPY src/${SERVICE_TYPE}-${SERVICE}/package.json ./src/${SERVICE_TYPE}-${SERVICE}/
RUN yarn install

COPY src/${SERVICE_TYPE}-${SERVICE} ./src/${SERVICE_TYPE}-${SERVICE}

RUN yarn workspace ${SERVICE} build

RUN ls ./src/${SERVICE_TYPE}-${SERVICE}/dist

RUN yarn workspace ${SERVICE} run test; exit 0

FROM node:lts-alpine
ARG SERVICE_TYPE
ARG SERVICE
ENV WORKSPACE ${SERVICE}
WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/src/${SERVICE_TYPE}-${SERVICE}/dist/lib.node.js ./index.js

CMD ["node", "index.js"]
