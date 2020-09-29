FROM alpine as certs
RUN apk update && apk add ca-certificates

FROM busybox
COPY --from=certs /etc/ssl/certs /etc/ssl/certs
COPY cdepot/cdepot /home/
EXPOSE 8002
CMD /home/cdepot