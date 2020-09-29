FROM alpine as certs
RUN apk update && apk add ca-certificates

FROM busybox
COPY --from=certs /etc/ssl/certs /etc/ssl/certs
COPY csidecar /home/
EXPOSE 8080
CMD echo ${ECS_CONTAINER_METADATA_URI_V4}; /home/csidecar