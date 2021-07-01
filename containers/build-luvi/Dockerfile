FROM alpine
RUN apk update && apk upgrade && apk add cmake ninja git build-base openssl-dev curl
RUN git clone --recursive https://github.com/luvit/luvi.git /luvi
WORKDIR /luvi
ENV GENERATOR Ninja
RUN make regular-shared
RUN make test
RUN build/luvi -v || true
