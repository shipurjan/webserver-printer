FROM node:alpine
RUN npm install -g http-server
WORKDIR /app
COPY index.html .
EXPOSE 3000
CMD ["http-server", "-p", "3000"]
