FROM golang:1.24 AS builder
WORKDIR /workspace
COPY . .
RUN CGO_ENABLED=0 go build -mod=mod -o /server ./cmd/

FROM ubuntu:20.04
RUN groupadd -r app && useradd -r -g app -m app
COPY --from=builder /server /server
RUN chown app:app /server
USER app
ENV FUNC_NAME=HelloWorld
EXPOSE 8080
ENTRYPOINT ["/server"]
