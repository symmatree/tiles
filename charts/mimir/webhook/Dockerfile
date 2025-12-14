ARG BASE_IMAGE=node
ARG BASE_TAG=alpine
FROM $BASE_IMAGE:$BASE_TAG

RUN apk upgrade --no-cache
WORKDIR /app

RUN npm i nunjucks axios

COPY . .

EXPOSE 3000

CMD ["node", "index.js"]
