FROM node:lts as builder

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm install

COPY public ./public
COPY src ./src

RUN npm run build:bs

RUN npm run build:js

RUN npm run test -- --coverage; exit 0

FROM nginx:alpine

COPY --from=builder /usr/src/app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
