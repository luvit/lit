FROM alpine
RUN apk update && apk upgrade && apk add cmake ninja git build-base
RUN git clone --recursive https://github.com/luvit/luvi.git /luvi
WORKDIR /luvi
ENV GENERATOR Ninja
RUN make regular test
RUN apk add curl
RUN curl https://lit.luvit.io/packages/luvit/lit/latest.zip > lit.zip
RUN build/luvi lit.zip -- make lit.zip lit build/luvi
RUN ./lit -v
CMD ash
