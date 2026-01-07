FROM node:18-alpine AS builder

WORKDIR /app

RUN npm install -g typescript

COPY app.ts index.html styles.css ./

RUN tsc app.ts --target es6 --lib "es6,dom" --outFile app.js

FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY --from=builder /app/index.html /usr/share/nginx/html/
COPY --from=builder /app/styles.css /usr/share/nginx/html/
COPY --from=builder /app/app.js /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]