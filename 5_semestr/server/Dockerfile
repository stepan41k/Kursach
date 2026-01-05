FROM golang:1.22-alpine

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bank ./cmd/bank/main.go

FROM alpine:latest

WORKDIR /app

COPY --from=0 /src/bank .

EXPOSE 3030

CMD ["./bank"]