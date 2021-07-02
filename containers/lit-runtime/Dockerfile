FROM alpine AS build
RUN apk update && apk upgrade && apk add cmake ninja git build-base openssl-dev curl
RUN git clone --recursive https://github.com/luvit/luvi.git /luvi
WORKDIR /luvi
ENV GENERATOR Ninja
RUN make regular-shared
RUN make test
RUN build/luvi -v || true
RUN apk add curl
RUN curl -L https://lit.luvit.io/packages/luvit/lit/latest.zip -o lit.zip

FROM alpine AS runtime
RUN apk add libgcc --no-cache
COPY --from=build /luvi/build/luvi /usr/bin/luvi
COPY --from=build /luvi/lit.zip /lit.zip
RUN cp /usr/bin/luvi /usr/bin/lit && cat /lit.zip >> /usr/bin/lit && rm lit.zip

RUN luvi -v || true
RUN lit -v || true
WORKDIR /workdir
CMD ["ash"]