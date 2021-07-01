FROM alpine
RUN apk add libgcc --no-cache
ADD luvi /usr/bin/
ADD lit /usr/bin/
RUN luvi -v || true
RUN lit -v || true
WORKDIR /workdir
CMD ["ash"]