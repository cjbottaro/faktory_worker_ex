FROM alpine:3.13 AS goreman

RUN apk add --no-cache go git
RUN GOPATH=/ go get github.com/mattn/goreman

FROM contribsys/faktory:1.5.1

RUN apk add --no-cache stunnel openssl
RUN openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -nodes -subj '/CN=localhost'
COPY --from=goreman /bin/goreman /usr/local/bin/
ADD Procfile stunnel.conf /
ENTRYPOINT [ "goreman" ]
CMD [ "start" ]