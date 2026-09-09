FROM alpine:3.23@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40 AS builder

ARG RATHENA_REF=e985006171d2eb320ee512a653f4c83aea3d81b6
ARG PACKETVER=20211103

RUN apk add --no-cache bash ca-certificates cmake g++ gcc git linux-headers make mariadb-dev zlib-dev
WORKDIR /src
RUN git clone https://github.com/rathena/rathena.git . \
 && git checkout "${RATHENA_REF}" \
 && ./configure --enable-packetver="${PACKETVER}" \
 && make -j"$(nproc)" server

FROM alpine:3.23@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40

RUN apk add --no-cache bash ca-certificates libstdc++ mariadb-client mariadb-connector-c zlib \
 && addgroup -g 10001 rathena \
 && adduser -D -u 10001 -G rathena rathena
WORKDIR /rathena
COPY --from=builder --chown=rathena:rathena /src /rathena
COPY --chown=rathena:rathena entrypoint.sh /usr/local/bin/rathena-entrypoint
RUN chmod 0755 /usr/local/bin/rathena-entrypoint \
 && mkdir -p /rathena/conf/import /rathena/log \
 && chown -R rathena:rathena /rathena/conf/import /rathena/log

USER 10001:10001
EXPOSE 6900 6121 5121
ENTRYPOINT ["/usr/local/bin/rathena-entrypoint"]
